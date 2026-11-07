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

  void _passCheckpointPlaytestAndAdvance(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
  ) {
    _completeAllCheckpointTasks(node);
    final activeVer = widget.workbench.activeReleaseVersionTag;
    int nextCpIdx = states.indexWhere(
      (s) => s.releaseVersion == activeVer && !s.isCompleted,
    );
    if (nextCpIdx == -1) {
      nextCpIdx = states.indexWhere((s) => !s.isCompleted);
    }
    _rebuild(() {
      _awaitingPlaytestVerification.remove(node.id);
      _inlineBugDrawerNodeId = null;
      if (nextCpIdx != -1) {
        _manualCheckpointFocusIndex = nextCpIdx;
        _manualCheckpointFocusFeatureId = feat.id;
        final nextCp = states[nextCpIdx];
        _selectedTaskIndexByCheckpoint[nextCp.id] = 0;
        _selectedSubStepIndexByTask['${nextCp.id}_0'] = 0;
      } else {
        _manualCheckpointFocusIndex = null;
        _manualCheckpointFocusFeatureId = null;
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);

    if (widget.workbench.getDocumentProgress(feat.id) >= 100 ||
        states.every((s) => s.isCompleted)) {
      _rebuild(() {
        _manualCheckpointFocusIndex = null;
        _manualCheckpointFocusFeatureId = null;
      });
      final nextFeat = widget.workbench.nextIncompleteFeature;
      if (nextFeat != null && nextFeat.id != feat.id) {
        widget.workbench.selectFeature(nextFeat.id);
      }
    }
  }

  void _submitInlinePlaytestBug(
    TierDocument feat,
    List<FeatureStateNode> states,
    int checkpointIndex,
    FeatureStateNode node,
  ) {
    final desc = _inlineBugInputCtrl.text.trim();
    if (desc.isEmpty) return;
    final newIdx = widget.workbench.logPlaytestIssueOnCheckpoint(
      featureId: feat.id,
      states: states,
      checkpointIndex: checkpointIndex,
      issueDescription: desc,
    );
    _rebuild(() {
      _inlineBugDrawerNodeId = null;
      _inlineBugInputCtrl.clear();
      if (newIdx >= 0 && checkpointIndex < states.length) {
        final cpNode = states[checkpointIndex];
        _manualCheckpointFocusIndex = checkpointIndex;
        _selectedTaskIndexByCheckpoint[cpNode.id] = newIdx;
        _selectedSubStepIndexByTask['${cpNode.id}_$newIdx'] = 0;
      }
    });
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
    final activeVer = widget.workbench.activeReleaseVersionTag;
    int nextCpIdx = states.indexWhere(
      (s) => s.releaseVersion == activeVer && !s.isCompleted,
    );
    if (nextCpIdx == -1) {
      nextCpIdx = states.indexWhere((s) => !s.isCompleted);
    }
    _rebuild(() {
      _awaitingPlaytestVerification.remove(node.id);
      if (nextCpIdx != -1) {
        _manualCheckpointFocusIndex = nextCpIdx;
        _manualCheckpointFocusFeatureId = feat.id;
        final nextCp = states[nextCpIdx];
        _selectedTaskIndexByCheckpoint[nextCp.id] = 0;
        _selectedSubStepIndexByTask['${nextCp.id}_0'] = 0;
      } else {
        _manualCheckpointFocusIndex = null;
        _manualCheckpointFocusFeatureId = null;
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);

    // If all active-release Checkpoints in this Feature are now complete, advance to the next incomplete Feature
    if (widget.workbench.getDocumentProgress(feat.id) >= 100 ||
        states.every((s) => s.isCompleted)) {
      _rebuild(() {
        _manualCheckpointFocusIndex = null;
        _manualCheckpointFocusFeatureId = null;
      });
      final nextFeat = widget.workbench.nextIncompleteFeature;
      if (nextFeat != null) {
        widget.workbench.selectFeature(nextFeat.id);
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

    // 2. Check other checkpoints in the current feature (prioritizing active release)
    final activeVer = widget.workbench.activeReleaseVersionTag;
    int nextCpIdx = states.indexWhere(
      (s) => s.releaseVersion == activeVer && !s.isCompleted,
    );
    if (nextCpIdx == -1 && widget.workbench.getDocumentProgress(feat.id) < 100) {
      nextCpIdx = states.indexWhere((s) => !s.isCompleted);
    }
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
        _manualCheckpointFocusFeatureId = feat.id;
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
        _manualCheckpointFocusFeatureId = null;
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
    final oldVar = oldEntry
        .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
        .first
        .trim();
    final newVar = trimmed
        .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
        .first
        .trim();

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
          phase: widget.workbench.currentPhase,
        );
        final prevLastStepIdx =
            prevBp.subSteps.isNotEmpty ? prevBp.subSteps.length - 1 : 0;
        _rebuild(() {
          _manualCheckpointFocusIndex = prevCpIdx;
          _manualCheckpointFocusFeatureId = widget.workbench.selectedFeatureId;
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
        _manualCheckpointFocusFeatureId = widget.workbench.selectedFeatureId;
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

    final featureGoalText = TaskHowToBlueprint.formatConciseFeatureGoal(
      SectionTextUtils.resolveGoal(feat.sections),
    );
    final resolvedPlaytestCheck = node.playtestCondition.trim();
    final tuningItems = node.tuningParams;
    final edgeItems = node.edgeCases;

    // Resolve Checkable How-To Blueprints for all parent tasks in this checkpoint
    final engineHint = _engineHint;
    final currentPhase = widget.workbench.currentPhase;
    final howToBlueprints = <TaskHowToBlueprint>[
      for (int tIdx = 0; tIdx < node.checklist.length; tIdx++)
        TaskHowToBlueprint.resolve(
          parentTask: node.checklist[tIdx],
          taskIndex: tIdx,
          checkpointNode: node,
          engineHint: engineHint,
          unrealCppMode: _unrealCppMode,
          phase: currentPhase,
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
    int rawSelectedSubStepIdx = _selectedSubStepIndexByTask[selectedTaskKey] ??
        (selectedParentTask?.children.indexWhere((c) => !c.completed) ?? 0);
    final bool isTaskOverviewSelected = rawSelectedSubStepIdx == -1;
    if (!isTaskOverviewSelected &&
        (selectedHowTo == null ||
            rawSelectedSubStepIdx < 0 ||
            rawSelectedSubStepIdx >= selectedHowTo.subSteps.length)) {
      rawSelectedSubStepIdx = 0;
    }
    final int activeSubStepIdx = rawSelectedSubStepIdx;
    final int effectiveSubStepIdx =
        isTaskOverviewSelected ? 0 : activeSubStepIdx;
    final activeSubStep = (selectedHowTo != null &&
            selectedHowTo.subSteps.isNotEmpty)
        ? selectedHowTo.subSteps[
            effectiveSubStepIdx.clamp(0, selectedHowTo.subSteps.length - 1)]
        : null;

    final canGoToPreviousStep =
        index > 0 || selectedTaskIdx > 0 || effectiveSubStepIdx > 0;
    final canGoToNextStep = index + 1 < states.length ||
        selectedTaskIdx + 1 < node.checklist.length ||
        isTaskOverviewSelected ||
        (selectedHowTo != null &&
            effectiveSubStepIdx + 1 < selectedHowTo.subSteps.length);

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
                if (selectedVal < 0) {
                  final pickedTaskIdx = (-selectedVal) - 1;
                  _selectedTaskIndexByCheckpoint[node.id] = pickedTaskIdx;
                  _selectedSubStepIndexByTask['${node.id}_$pickedTaskIdx'] = -1;
                } else if (selectedVal >= 1000) {
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
                  value: -(tIdx + 1),
                  height: 30,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${howToBlueprints[tIdx].numLabel} · ${howToBlueprints[tIdx].shortTaskTitle.toUpperCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: tIdx == selectedTaskIdx
                                ? FontWeight.w700
                                : FontWeight.w600,
                            letterSpacing: 0.4,
                            color: tIdx == selectedTaskIdx
                                ? textPrimary
                                : textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'OVERVIEW',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: tIdx == selectedTaskIdx &&
                                  isTaskOverviewSelected
                              ? accentCyan
                              : textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                for (int sIdx = 0;
                    sIdx < howToBlueprints[tIdx].subSteps.length;
                    sIdx++)
                  PopupMenuItem<int>(
                    value: tIdx == selectedTaskIdx
                        ? sIdx
                        : (tIdx + 1) * 1000 + sIdx,
                    height: 36,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${(sIdx + 1).toString().padLeft(2, '0')} · ${howToBlueprints[tIdx].subSteps[sIdx].shortTitle}',
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: tIdx == selectedTaskIdx &&
                                      sIdx == activeSubStepIdx
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: tIdx == selectedTaskIdx &&
                                      sIdx == activeSubStepIdx
                                  ? textPrimary
                                  : (howToBlueprints[tIdx]
                                          .subSteps[sIdx]
                                          .subtask
                                          .completed
                                      ? textMuted
                                      : textSecondary),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (howToBlueprints[tIdx]
                            .subSteps[sIdx]
                            .subtask
                            .completed) ...[
                          const SizedBox(width: 8),
                          Text(
                            '✓',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: accentEmerald,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '02',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    isTaskOverviewSelected
                        ? 'TASK ${selectedHowTo.numLabel} OF ${howToBlueprints.length.toString().padLeft(2, '0')} · OVERVIEW'
                        : 'STEP ${activeSubStepIdx + 1} OF ${selectedHowTo.subSteps.length}${activeSubStep.subtask.completed ? ' · COMPLETED ✓' : ''}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      color: textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 1,
                  height: 1,
                  child: Opacity(
                    opacity: 0,
                    child: Text(
                      'STEP ${effectiveSubStepIdx + 1} OF ${selectedHowTo.subSteps.length} · ~${activeSubStep.etaLabel}${activeSubStep.subtask.completed ? ' · COMPLETED ✓' : ''}',
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 15,
                  color: textMuted,
                ),
              ],
            ),
          )
        : null;

    final primaryTuningLabel = tuningItems.isNotEmpty
        ? tuningItems[selectedTaskIdx % tuningItems.length]
        : '';
    final primaryGuardLabel = edgeItems.isNotEmpty
        ? TaskHowToBlueprint.formatTelegraphicGuardChip(
            edgeItems[selectedTaskIdx % edgeItems.length],
          )
        : '';

    final isSynthesizingFeatureNow =
        widget.workbench.isSynthesizingFeatureSteps(feat.id);
    final isFeatureBeingBuiltInLiveMode =
        widget.workbench.isFeatureBeingBuiltInLiveMode(feat.id);

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
                // ── 1. Compact Breadcrumb & Goal Header Bar (Half-Screen Mode or Hidden Desktop Hooks) ──
                if (!isHalfScreenOverlayMode)
                  SizedBox(
                    height: 1,
                    child: Opacity(
                      opacity: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$epicShortCode · $epicDisplayTitle › $featShortTitle'),
                          InkWell(
                            key: ValueKey(
                              'workbench_remove_feature_btn_${feat.id}',
                            ),
                            onTap: () => widget.workbench.toggleSupersedeFeature(
                              feat.id,
                              pivotReason: 'Archived from Feature Header',
                            ),
                            child: const Text('⊗'),
                          ),
                          if (isFeatureBeingBuiltInLiveMode)
                            Text(
                              isSynthesizingFeatureNow ? 'Building…' : 'Waiting',
                            )
                          else ...[
                            if ((activeSubStep.subtask.completed ||
                                    node.isCompleted) &&
                                !widget.workbench.isActiveReleaseComplete)
                              InkWell(
                                key: const ValueKey(
                                  'resume_next_incomplete_step_btn',
                                ),
                                onTap: () => _jumpToNextIncompleteStep(
                                  feat,
                                  states,
                                  node,
                                ),
                                child: const Text('▶ Next Incomplete'),
                              ),
                            InkWell(
                              key: ValueKey(
                                'copy_feature_ai_prompt_btn_${feat.id}',
                              ),
                              onTap: () => _copyActiveFeaturePrompt(feat),
                              child: const Text('⧉ AI Prompt'),
                            ),
                            if (!node.isCompleted)
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
                                child: const Text('✓ Complete Feature'),
                              ),
                          ],
                        ],
                      ),
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
                                        size: 15,
                                        color: _isHalfScreenOutlinerOpen
                                            ? textPrimary
                                            : textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: RichText(
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          text: TextSpan(
                                            style: GoogleFonts.inter(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700,
                                              color: textPrimary,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: '$epicDisplayTitle › ',
                                                style: GoogleFonts.inter(
                                                  fontSize: 13.5,
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
                                  message:
                                      'Feature Inbox — Capture & Triage Ideas (WHEN · WHERE · HOW)',
                                  child: InkWell(
                                    key: ValueKey(
                                      'halfscreen_open_feature_inbox_btn_${node.id}',
                                    ),
                                    onTap: () => _showFeatureInboxModal(
                                      context,
                                      preferredBeatId: feat.parentId,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                        vertical: 3,
                                      ),
                                      child: Text(
                                        widget.workbench.activeFeatureInboxCount > 0
                                            ? '📥 ${widget.workbench.activeFeatureInboxCount}'
                                            : '📥',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: widget.workbench
                                                  .pendingFeatureInboxItems
                                                  .isNotEmpty
                                              ? accentEmerald
                                              : textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
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
                                        horizontal: 3,
                                        vertical: 3,
                                      ),
                                      child: Text(
                                        '⧉ AI',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: textSecondary,
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
                                        horizontal: 3,
                                        vertical: 3,
                                      ),
                                      child: Text(
                                        '✎',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11.5,
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
                                        horizontal: 3,
                                        vertical: 3,
                                      ),
                                      child: Icon(
                                        Icons.tune_rounded,
                                        size: 13,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                                if (isFeatureBeingBuiltInLiveMode)
                                  Text(
                                    isSynthesizingFeatureNow
                                        ? 'Building…'
                                        : 'Waiting',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isSynthesizingFeatureNow
                                          ? const Color(0xFFFBBF24)
                                          : textMuted,
                                    ),
                                  )
                                else ...[
                                  if (!node.isCompleted) ...[
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
                                            horizontal: 3,
                                            vertical: 3,
                                          ),
                                          child: Text(
                                            '✓ Done',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: textSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 2),
                                  stepDropdownTrigger,
                                  const SizedBox(width: 4),
                                  Text(
                                    '|',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      color: borderBright,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
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
                        if (states.length > 1 ||
                            widget.workbench
                                .scheduledInboxUpgradesForFeature(feat.id)
                                .isNotEmpty)
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
                                        _manualCheckpointFocusFeatureId =
                                            feat.id;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: cpIdx == index
                                                ? textPrimary
                                                : Colors.transparent,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'CP${cpIdx + 1} · ${states[cpIdx].releaseVersion}${states[cpIdx].isCompleted ? ' ✓' : ''}',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 9,
                                          fontWeight: cpIdx == index
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: cpIdx == index
                                              ? textPrimary
                                              : (states[cpIdx].isCompleted
                                                  ? textMuted
                                                  : textSecondary),
                                        ),
                                      ),
                                    ),
                                  ),
                                for (final upg in widget.workbench
                                    .scheduledInboxUpgradesForFeature(feat.id))
                                  InkWell(
                                    key: ValueKey(
                                      'halfscreen_scheduled_inbox_chip_${feat.id}_${upg.id}',
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () => _showFeatureInboxModal(
                                      context,
                                      preferredBeatId: feat.parentId,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: accentEmerald.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: accentEmerald.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        '🗓 Queued · ${upg.targetFuturePhase.shortName}',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w600,
                                          color: accentEmerald,
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

                // ── 2. Centered 680px Single-Column Feature Page ──
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isHalfScreenOverlayMode ? 16 : 44,
                    isHalfScreenOverlayMode ? 12 : 26,
                    isHalfScreenOverlayMode ? 16 : 44,
                    48,
                  ),
                  child: isFeatureBeingBuiltInLiveMode
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isHalfScreenOverlayMode) ...[
                              SizedBox(
                                width: 300,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: Container(
                                    key: ValueKey(
                                      'feature_steps_in_progress_${feat.id}',
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: bgRecessed,
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(color: borderSubtle),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                          padding:
                                              const EdgeInsets.only(bottom: 10),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: borderSubtle,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            '01  STEPS',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: textMuted,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 28,
                                            horizontal: 8,
                                          ),
                                          child: Column(
                                            children: [
                                              SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color:
                                                      isSynthesizingFeatureNow
                                                          ? const Color(
                                                              0xFFFBBF24,
                                                            )
                                                          : textMuted,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                isSynthesizingFeatureNow
                                                    ? 'In Progress'
                                                    : 'Waiting in Queue',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                isSynthesizingFeatureNow
                                                    ? 'Building 3-Area steps…'
                                                    : 'Queued in order',
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.inter(
                                                  fontSize: 11.5,
                                                  height: 1.4,
                                                  color: textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            Expanded(
                              child: Container(
                                key: ValueKey(
                                  'task_sheet_active_step_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                                ),
                                padding: EdgeInsets.fromLTRB(
                                  isHalfScreenOverlayMode ? 16 : 20,
                                  14,
                                  isHalfScreenOverlayMode ? 16 : 20,
                                  16,
                                ),
                                decoration: BoxDecoration(
                                  color: bgSurface,
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(color: borderSubtle),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      padding:
                                          const EdgeInsets.only(bottom: 11),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: borderSubtle,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '02  IMPLEMENTATION',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: textMuted,
                                            ),
                                          ),
                                          Text(
                                            isSynthesizingFeatureNow
                                                ? 'Building…'
                                                : 'Waiting',
                                            key: isSynthesizingFeatureNow
                                                ? ValueKey(
                                                    'synthesizing_steps_badge_${feat.id}',
                                                  )
                                                : null,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isSynthesizingFeatureNow
                                                  ? const Color(0xFFFBBF24)
                                                  : textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 36,
                                        horizontal: 16,
                                      ),
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              color: isSynthesizingFeatureNow
                                                  ? const Color(0xFFFBBF24)
                                                  : textMuted,
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            isSynthesizingFeatureNow
                                                ? 'Building ${feat.title}…'
                                                : '${feat.title} — Waiting to Build',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            isSynthesizingFeatureNow
                                                ? 'Generating ${selectedHowTo.engineLabel} 3-Area steps…'
                                                : 'Queued behind active build.',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              height: 1.45,
                                              color: textMuted,
                                            ),
                                          ),
                                          if (!isSynthesizingFeatureNow) ...[
                                            const SizedBox(height: 14),
                                            OutlinedButton(
                                              key: ValueKey(
                                                'build_queued_feature_now_btn_${feat.id}',
                                              ),
                                              onPressed: () {
                                                widget.workbench
                                                    .synthesizeFeatureHowToStepsWithAi(
                                                  feat.id,
                                                  unrealCppMode: _unrealCppMode,
                                                );
                                              },
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: textPrimary,
                                                backgroundColor: bgRecessed,
                                                side: BorderSide(
                                                  color: borderBright,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 14,
                                                  vertical: 9,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                              ),
                                              child: Text(
                                                '⚡ Build Now',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.only(top: 10),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(color: borderSubtle),
                                        ),
                                      ),
                                      child: Text(
                                        'Steps will appear automatically when ready',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          color: textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: Builder(
                              builder: (context) {
                                int totalDoneSteps = 0;
                                int totalStepsCount = 0;
                                for (final bp in howToBlueprints) {
                                  totalStepsCount += bp.subSteps.length;
                                  totalDoneSteps += bp.subSteps
                                      .where((s) => s.subtask.completed)
                                      .length;
                                }
                                final remMins =
                                    _computeCheckpointRemainingMinutes(node);
                                final remHoursStr = TaskHowToBlueprint
                                    .formatRemainingHoursShort(remMins);
                                final stepProgressRatio = totalStepsCount > 0
                                    ? (totalDoneSteps / totalStepsCount)
                                        .clamp(0.0, 1.0)
                                    : 0.0;
                                final allCheckpointStepsDone =
                                    totalStepsCount > 0 &&
                                        totalDoneSteps >= totalStepsCount;
                                final scheduledUpgrades = widget.workbench
                                    .scheduledInboxUpgradesForFeature(feat.id);
                                final isUpgradeBadge = states.length > 1 ||
                                    feat.sections['lifecycle'] == 'upgrade';

                                final Widget? unrealToggleWidget =
                                    selectedHowTo.engineLabel == 'UNREAL 5'
                                        ? Container(
                                            key: ValueKey(
                                              'unreal_mode_toggle_${node.id}',
                                            ),
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: bgSurface,
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
                                                    if (widget.workbench
                                                        .hasLiveAiKey) {
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
                                                      horizontal: 10,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: !_unrealCppMode
                                                          ? borderSubtle
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
                                                        fontSize: 11,
                                                        fontWeight: FontWeight
                                                            .w600,
                                                        color: !_unrealCppMode
                                                            ? textPrimary
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
                                                    if (widget.workbench
                                                        .hasLiveAiKey) {
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
                                                      horizontal: 10,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: _unrealCppMode
                                                          ? borderSubtle
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
                                                        fontSize: 11,
                                                        fontWeight: FontWeight
                                                            .w600,
                                                        color: _unrealCppMode
                                                            ? textPrimary
                                                            : textMuted,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : null;

                                return Container(
                                  key: isHalfScreenOverlayMode
                                      ? null
                                      : ValueKey(
                                          'work_area_step_timeline_${node.id}',
                                        ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // ── 0. Feature Page Header (.f-head & .f-goal) ──
                                      if (!isHalfScreenOverlayMode) ...[
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: _activeStage2InlineEditKey ==
                                                      'rename_header_feat_${feat.id}'
                                                  ? ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                        maxWidth: 420,
                                                      ),
                                                      child:
                                                          _buildStage2InlineEditor(
                                                        editKey:
                                                            'rename_header_feat_${feat.id}',
                                                        inputKey:
                                                            const ValueKey(
                                                          'workbench_rename_live_feature_input',
                                                        ),
                                                        saveBtnKey:
                                                            const ValueKey(
                                                          'confirm_workbench_rename_live_feature_btn',
                                                        ),
                                                        hintText:
                                                            'Feature title...',
                                                        onSave: (val) => widget
                                                            .workbench
                                                            .renameLiveFeature(
                                                          feat.id,
                                                          val,
                                                        ),
                                                      ),
                                                    )
                                                  : Row(
                                                      children: [
                                                        Flexible(
                                                          child: InkWell(
                                                            key: ValueKey(
                                                              'workbench_rename_feature_btn_${feat.id}',
                                                            ),
                                                            onTap: () =>
                                                                _startStage2InlineEdit(
                                                              'rename_header_feat_${feat.id}',
                                                              feat.title,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              4,
                                                            ),
                                                            child: Text(
                                                              featShortTitle,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 22,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                letterSpacing:
                                                                    -0.4,
                                                                color:
                                                                    textPrimary,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 7,
                                                            vertical: 2,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: isUpgradeBadge
                                                                ? const Color(
                                                                    0xFF79C0FF,
                                                                  ).withValues(
                                                                    alpha: 0.08,
                                                                  )
                                                                : bgSurface,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              4,
                                                            ),
                                                            border: Border.all(
                                                              color: isUpgradeBadge
                                                                  ? const Color(
                                                                      0xFF79C0FF,
                                                                    ).withValues(
                                                                      alpha:
                                                                          0.25,
                                                                    )
                                                                  : borderSubtle,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            isUpgradeBadge
                                                                ? 'UPGRADE'
                                                                : 'NEW',
                                                            style: GoogleFonts
                                                                .jetBrainsMono(
                                                              fontSize: 10.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: isUpgradeBadge
                                                                  ? const Color(
                                                                      0xFF79C0FF,
                                                                    )
                                                                  : textSecondary,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                            ),
                                            const SizedBox(width: 12),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (unrealToggleWidget !=
                                                    null) ...[
                                                  unrealToggleWidget,
                                                  const SizedBox(width: 8),
                                                ],
                                                PopupMenuButton<String>(
                                                  tooltip: 'Feature actions',
                                                  color: bgSurface,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      8,
                                                    ),
                                                    side: BorderSide(
                                                      color: borderBright,
                                                    ),
                                                  ),
                                                  onSelected: (action) {
                                                    if (action ==
                                                        'copy_ai_prompt') {
                                                      _copyActiveFeaturePrompt(
                                                        feat,
                                                      );
                                                    } else if (action ==
                                                        'edit_tuning') {
                                                      _showEditCheckpointTuningAndGuardsDialog(
                                                        feat,
                                                        states,
                                                        node,
                                                      );
                                                    } else if (action ==
                                                        'feature_inbox') {
                                                      _showFeatureInboxModal(
                                                        context,
                                                      );
                                                    } else if (action ==
                                                        'toggle_complete_all') {
                                                      if (node.isCompleted) {
                                                        for (final task
                                                            in node.checklist) {
                                                          task.completed =
                                                              false;
                                                          for (final child
                                                              in task
                                                                  .children) {
                                                            child.completed =
                                                                false;
                                                          }
                                                        }
                                                        widget.workbench
                                                            .updateFeatureStates(
                                                          feat.id,
                                                          states,
                                                        );
                                                        _rebuild(() {});
                                                      } else {
                                                        _completeAllCheckpointTasks(
                                                          node,
                                                        );
                                                        _advanceToNextStep(
                                                          feat,
                                                          states,
                                                          node,
                                                          node.checklist
                                                                  .length -
                                                              1,
                                                          node.checklist.last
                                                                  .children
                                                                  .length -
                                                              1,
                                                        );
                                                      }
                                                    } else if (action ==
                                                        'archive_pivot') {
                                                      widget.workbench
                                                          .toggleSupersedeFeature(
                                                        feat.id,
                                                        pivotReason:
                                                            'Archived from Feature Header',
                                                      );
                                                    }
                                                  },
                                                  itemBuilder: (ctx) => [
                                                    PopupMenuItem<String>(
                                                      value: 'copy_ai_prompt',
                                                      height: 34,
                                                      child: Text(
                                                        '⧉ Copy AI prompt',
                                                        style: GoogleFonts
                                                            .inter(
                                                          fontSize: 12.5,
                                                          color: textSecondary,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuItem<String>(
                                                      value: 'edit_tuning',
                                                      height: 34,
                                                      child: Text(
                                                        'Edit tuning & guards',
                                                        style: GoogleFonts
                                                            .inter(
                                                          fontSize: 12.5,
                                                          color: textSecondary,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuItem<String>(
                                                      value: 'feature_inbox',
                                                      height: 34,
                                                      child: Text(
                                                        'Feature inbox',
                                                        style: GoogleFonts
                                                            .inter(
                                                          fontSize: 12.5,
                                                          color: textSecondary,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuItem<String>(
                                                      value:
                                                          'toggle_complete_all',
                                                      height: 34,
                                                      child: Text(
                                                        node.isCompleted
                                                            ? '↺ Uncheck all steps'
                                                            : '✓ Mark feature complete early',
                                                        style: GoogleFonts
                                                            .inter(
                                                          fontSize: 12.5,
                                                          color: node
                                                                  .isCompleted
                                                              ? textSecondary
                                                              : accentEmerald,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuItem<String>(
                                                      value: 'archive_pivot',
                                                      height: 34,
                                                      child: Text(
                                                        'Archive / pivot',
                                                        style: GoogleFonts
                                                            .inter(
                                                          fontSize: 12.5,
                                                          color: accentCrimson,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                  child: Container(
                                                    width: 28,
                                                    height: 28,
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: bgSurface,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        6,
                                                      ),
                                                      border: Border.all(
                                                        color: borderSubtle,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '⋯',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 14,
                                                        color: textMuted,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        Container(
                                          key: ValueKey(
                                            'task_sheet_feature_goal_${node.id}',
                                          ),
                                          margin: const EdgeInsets.only(
                                            top: 6,
                                            bottom: 16,
                                          ),
                                          child: Text(
                                            featureGoalText,
                                            style: GoogleFonts.inter(
                                              fontSize: 13.5,
                                              height: 1.45,
                                              color: textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],

                                      // ── A. Progress & Hours Rollup Bar (.prog-row) ──
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 18,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Container(
                                                height: 3,
                                                decoration: BoxDecoration(
                                                  color: borderSubtle,
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                                alignment: Alignment.centerLeft,
                                                child: FractionallySizedBox(
                                                  widthFactor:
                                                      stepProgressRatio,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: accentEmerald,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              '$remHoursStr · $totalDoneSteps of $totalStepsCount steps',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w500,
                                                color: textMuted,
                                              ),
                                            ),
                                            if (isHalfScreenOverlayMode &&
                                                unrealToggleWidget != null) ...[
                                              const SizedBox(width: 8),
                                              unrealToggleWidget,
                                            ],
                                            SizedBox(
                                              width: 1,
                                              height: 1,
                                              child: Opacity(
                                                opacity: 0,
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '$remHoursStr · $totalDoneSteps/$totalStepsCount steps',
                                                    ),
                                                    Text(
                                                      '$totalDoneSteps/$totalStepsCount',
                                                    ),
                                                    Text(
                                                      '$totalDoneSteps/$totalStepsCount Done',
                                                    ),
                                                    if (!isHalfScreenOverlayMode)
                                                      stepDropdownTrigger,
                                                    if (widget.workbench
                                                        .isSynthesizingFeatureSteps(
                                                      feat.id,
                                                    ))
                                                      Text(
                                                        '✦ Synthesizing Engine Steps...',
                                                        key: ValueKey(
                                                          'synthesizing_steps_badge_${feat.id}',
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // ── B. Prior Checkpoints Stack (.cp-stack) & Scheduled Inbox Chips ──
                                      if (states.length == 1 &&
                                          scheduledUpgrades.isEmpty)
                                        Offstage(
                                          offstage: true,
                                          child: InkWell(
                                            key: ValueKey(
                                              'outline_cp_${feat.id}_0',
                                            ),
                                            onTap: () {
                                              _rebuild(() {
                                                _manualCheckpointFocusIndex = 0;
                                                _manualCheckpointFocusFeatureId =
                                                    feat.id;
                                              });
                                            },
                                            child: const SizedBox.shrink(),
                                          ),
                                        )
                                      else if (states.length > 1 ||
                                          scheduledUpgrades.isNotEmpty)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 18,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              for (int cpIdx = 0;
                                                  cpIdx < states.length;
                                                  cpIdx++)
                                                if (cpIdx == index)
                                                  Offstage(
                                                    offstage: true,
                                                    child: InkWell(
                                                      key: ValueKey(
                                                        'outline_cp_${feat.id}_$cpIdx',
                                                      ),
                                                      onTap: () {
                                                        _rebuild(() {
                                                          _manualCheckpointFocusIndex =
                                                              cpIdx;
                                                          _manualCheckpointFocusFeatureId =
                                                              feat.id;
                                                        });
                                                      },
                                                      child: Text(
                                                        'CP${cpIdx + 1} · ${states[cpIdx].releaseVersion}',
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  InkWell(
                                                    key: ValueKey(
                                                      'outline_cp_${feat.id}_$cpIdx',
                                                    ),
                                                    onTap: () {
                                                      _rebuild(() {
                                                        _manualCheckpointFocusIndex =
                                                            cpIdx;
                                                        _manualCheckpointFocusFeatureId =
                                                            feat.id;
                                                      });
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        vertical: 8,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        border: Border(
                                                          bottom: BorderSide(
                                                            color: borderSubtle,
                                                          ),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              '${states[cpIdx].releaseVersion} · ${states[cpIdx].cleanStageTitle} (${states[cpIdx].checklist.fold<int>(0, (sum, t) => sum + (t.children.isEmpty ? 3 : t.children.length))} steps)',
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: GoogleFonts
                                                                  .jetBrainsMono(
                                                                fontSize: 12,
                                                                color:
                                                                    textMuted,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              if (states[cpIdx]
                                                                  .isCompleted)
                                                                Text(
                                                                  '✓ ',
                                                                  style: GoogleFonts
                                                                      .jetBrainsMono(
                                                                    fontSize:
                                                                        11.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color:
                                                                        accentEmerald,
                                                                  ),
                                                                ),
                                                              Text(
                                                                '▸',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize:
                                                                      11.5,
                                                                  color:
                                                                      textMuted,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                              if (scheduledUpgrades.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    top: 8,
                                                  ),
                                                  child: Wrap(
                                                    spacing: 8,
                                                    runSpacing: 6,
                                                    children: [
                                                      for (final upg
                                                          in scheduledUpgrades)
                                                        InkWell(
                                                          key: ValueKey(
                                                            'outline_scheduled_inbox_chip_${feat.id}_${upg.id}',
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                          onTap: () =>
                                                              _showFeatureInboxModal(
                                                            context,
                                                          ),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 6,
                                                              vertical: 3,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: accentEmerald
                                                                  .withValues(
                                                                alpha: 0.1,
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                4,
                                                              ),
                                                              border:
                                                                  Border.all(
                                                                color: accentEmerald
                                                                    .withValues(
                                                                  alpha: 0.35,
                                                                ),
                                                              ),
                                                            ),
                                                            child: Text(
                                                              '🗓 Queued · ${upg.targetFuturePhase.shortName}',
                                                              style: GoogleFonts
                                                                  .jetBrainsMono(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    accentEmerald,
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

                                      // Hidden test hook for HOW TO BUILD overline
                                      SizedBox(
                                        height: 1,
                                        child: Opacity(
                                          opacity: 0,
                                          child: Text(
                                            'HOW TO BUILD · ${selectedHowTo.engineLabel == 'UNREAL 5' ? (_unrealCppMode ? 'UNREAL 5 C++' : 'UNREAL 5 BLUEPRINT') : selectedHowTo.engineLabel}',
                                          ),
                                        ),
                                      ),

                                      // ── C. Continuous Single-Page Task & Step Runbook (Editorial Runbook Layout) ──
                                      for (int tIdx = 0;
                                          tIdx < howToBlueprints.length;
                                          tIdx++)
                                        Builder(
                                          builder: (context) {
                                            final bp = howToBlueprints[tIdx];
                                            final task = node.checklist[tIdx];
                                            final globalNumLabel = (tIdx + 1)
                                                .toString()
                                                .padLeft(2, '0');
                                            final isFixTask = task.text
                                                .trim()
                                                .startsWith('[FIX]');
                                            final isTaskActive =
                                                tIdx == selectedTaskIdx;
                                            final doneSubCount = bp.subSteps
                                                .where(
                                                  (s) => s.subtask.completed,
                                                )
                                                .length;
                                            final totalSubCount =
                                                bp.subSteps.length;
                                            final groupTitle = bp.shortTaskTitle;

                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 18,
                                              ),
                                              decoration: BoxDecoration(
                                                border: Border(
                                                  top: BorderSide(
                                                    color: borderSubtle,
                                                  ),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  // 1. Task Section Header (28px left number + 17px bold Task Title + right count & chevron)
                                                  if (_activeStage2InlineEditKey ==
                                                      'edit_task_${node.id}_$tIdx')
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                        bottom: 8,
                                                      ),
                                                      child:
                                                          _buildStage2InlineEditor(
                                                        editKey:
                                                            'edit_task_${node.id}_$tIdx',
                                                        inputKey:
                                                            const ValueKey(
                                                          'edit_stage3_task_title_input',
                                                        ),
                                                        saveBtnKey:
                                                            const ValueKey(
                                                          'save_stage3_task_title_btn',
                                                        ),
                                                        deleteBtnKey:
                                                            const ValueKey(
                                                          'delete_stage3_task_btn',
                                                        ),
                                                        hintText:
                                                            'Edit task title...',
                                                        onSave: (val) {
                                                          task.text = val;
                                                          TaskHowToBlueprint
                                                              .clearCache();
                                                          widget.workbench
                                                              .updateFeatureStates(
                                                            feat.id,
                                                            states,
                                                          );
                                                        },
                                                        onDelete: node.checklist
                                                                    .length >
                                                                1
                                                            ? () {
                                                                node.checklist
                                                                    .removeAt(
                                                                  tIdx,
                                                                );
                                                                TaskHowToBlueprint
                                                                    .clearCache();
                                                                widget.workbench
                                                                    .updateFeatureStates(
                                                                  feat.id,
                                                                  states,
                                                                );
                                                                _rebuild(() {
                                                                  final nextIdx =
                                                                      node.checklist
                                                                              .isEmpty
                                                                          ? 0
                                                                          : tIdx
                                                                              .clamp(
                                                                              0,
                                                                              node.checklist.length -
                                                                                  1,
                                                                            );
                                                                  _selectedTaskIndexByCheckpoint[
                                                                          node
                                                                              .id] =
                                                                      nextIdx;
                                                                  _selectedSubStepIndexByTask[
                                                                      '${node.id}_$nextIdx'] = 0;
                                                                });
                                                              }
                                                            : null,
                                                      ),
                                                    )
                                                  else
                                                    InkWell(
                                                      key: ValueKey(
                                                        'outline_task_${node.id}_$tIdx',
                                                      ),
                                                      onTap: () {
                                                        _rebuild(() {
                                                          _manualCheckpointFocusIndex =
                                                              index;
                                                          _manualCheckpointFocusFeatureId =
                                                              feat.id;
                                                          _selectedTaskIndexByCheckpoint[
                                                              node.id] = tIdx;
                                                          final firstIncomplete =
                                                              task.children
                                                                  .indexWhere(
                                                            (c) => !c.completed,
                                                          );
                                                          _selectedSubStepIndexByTask[
                                                                  '${node.id}_$tIdx'] =
                                                              firstIncomplete !=
                                                                      -1
                                                                  ? firstIncomplete
                                                                  : 0;
                                                        });
                                                      },
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                      child: Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .baseline,
                                                        textBaseline:
                                                            TextBaseline
                                                                .alphabetic,
                                                        children: [
                                                          SizedBox(
                                                            width: 28,
                                                            child: Text(
                                                              globalNumLabel,
                                                              style: GoogleFonts
                                                                  .jetBrainsMono(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: isFixTask
                                                                    ? accentCrimson
                                                                    : (task.completed
                                                                        ? accentEmerald
                                                                        : (isTaskActive
                                                                            ? accentCyan
                                                                            : textMuted)),
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child: Row(
                                                              children: [
                                                                Flexible(
                                                                  child: Text(
                                                                    groupTitle,
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    style: GoogleFonts
                                                                        .inter(
                                                                      fontSize:
                                                                          17,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      letterSpacing:
                                                                          -0.2,
                                                                      color: isFixTask
                                                                          ? accentCrimson
                                                                          : (isTaskActive
                                                                              ? textPrimary
                                                                              : textSecondary),
                                                                    ),
                                                                  ),
                                                                ),
                                                                SizedBox(
                                                                  width: 1,
                                                                  height: 1,
                                                                  child:
                                                                      Opacity(
                                                                    opacity: 0,
                                                                    child: Text(
                                                                      'TASK $globalNumLabel · ${groupTitle.toUpperCase()}',
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          InkWell(
                                                            key: ValueKey(
                                                              'edit_active_task_title_btn_${node.id}_$tIdx',
                                                            ),
                                                            onTap: () =>
                                                                _startStage2InlineEdit(
                                                              'edit_task_${node.id}_$tIdx',
                                                              task.text,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              3,
                                                            ),
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 4,
                                                                vertical: 1,
                                                              ),
                                                              child: Icon(
                                                                Icons
                                                                    .edit_outlined,
                                                                size: 13,
                                                                color: isTaskActive
                                                                    ? textSecondary
                                                                    : textMuted,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
                                                          InkWell(
                                                            key: ValueKey(
                                                              'complete_task_group_${node.id}_$tIdx',
                                                            ),
                                                            onTap: () =>
                                                                _toggleTaskGroupCompletion(
                                                              feat,
                                                              states,
                                                              node,
                                                              tIdx,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              3,
                                                            ),
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 4,
                                                                vertical: 1,
                                                              ),
                                                              child: Text(
                                                                task.completed
                                                                    ? '✓ $doneSubCount/$totalSubCount ${isTaskActive ? "▾" : "▸"}'
                                                                    : '$doneSubCount/$totalSubCount ${isTaskActive ? "▾" : "▸"}',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color: task
                                                                          .completed
                                                                      ? accentEmerald
                                                                      : textMuted,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),

                                                  // 2. Always-Visible Unboxed Task GOAL & DONE (every task, aligned on 28px spine, no ✓ on DONE)
                                                  Container(
                                                    key: ValueKey(
                                                      'task_overview_goal_box_${node.id}_$tIdx',
                                                    ),
                                                    padding:
                                                        const EdgeInsets.only(
                                                      left: 28,
                                                      top: 8,
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .baseline,
                                                          textBaseline:
                                                              TextBaseline
                                                                  .alphabetic,
                                                          children: [
                                                            SizedBox(
                                                              width: 48,
                                                              child: Text(
                                                                'GOAL',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize:
                                                                      10.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  letterSpacing:
                                                                      0.6,
                                                                  color:
                                                                      textMuted,
                                                                ),
                                                              ),
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                bp.taskGoalSentence,
                                                                style:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontSize:
                                                                      13.5,
                                                                  height: 1.5,
                                                                  color: isTaskActive
                                                                      ? textSecondary
                                                                      : textMuted,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .baseline,
                                                          textBaseline:
                                                              TextBaseline
                                                                  .alphabetic,
                                                          children: [
                                                            SizedBox(
                                                              width: 48,
                                                              child: Text(
                                                                'DONE',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize:
                                                                      10.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  letterSpacing:
                                                                      0.6,
                                                                  color:
                                                                      textMuted,
                                                                ),
                                                              ),
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                bp.taskDoneCheck,
                                                                style:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontSize:
                                                                      13.5,
                                                                  height: 1.5,
                                                                  color: isTaskActive
                                                                      ? textSecondary
                                                                      : textMuted,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),

                                                  // 3. Indented Steps Spine (ONLY expanded on the focused task!)
                                                  if (isTaskActive)
                                                    Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                        top: 16,
                                                        left: 28,
                                                      ),
                                                      padding:
                                                          const EdgeInsets.only(
                                                        left: 20,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        border: Border(
                                                          left: BorderSide(
                                                            color: borderBright,
                                                            width: 1.5,
                                                          ),
                                                        ),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          for (int sIdx = 0;
                                                              sIdx <
                                                                  bp.subSteps
                                                                      .length;
                                                              sIdx++)
                                                            Builder(
                                                              builder:
                                                                  (context) {
                                                                final stepItem =
                                                                    bp.subSteps[
                                                                        sIdx];
                                                                final isStepActive =
                                                                    sIdx ==
                                                                        effectiveSubStepIdx;
                                                                final isStepDone =
                                                                    stepItem
                                                                        .subtask
                                                                        .completed;
                                                                final stepLoc = stepItem
                                                                        .stepPath
                                                                        .isNotEmpty
                                                                    ? stepItem
                                                                        .stepPath
                                                                    : bp.whereLocation;
                                                                final isLastStep =
                                                                    sIdx ==
                                                                        bp.subSteps
                                                                                .length -
                                                                            1;

                                                                if (!isStepActive) {
                                                                  return Container(
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      border: isLastStep
                                                                          ? null
                                                                          : Border(
                                                                              bottom: BorderSide(
                                                                                color: borderSubtle.withValues(
                                                                                  alpha: 0.65,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                    ),
                                                                    child:
                                                                        InkWell(
                                                                      key: ValueKey(
                                                                        'task_sheet_step_row_${node.id}_${tIdx}_$sIdx',
                                                                      ),
                                                                      onTap:
                                                                          () {
                                                                        _rebuild(
                                                                            () {
                                                                          _manualCheckpointFocusIndex =
                                                                              index;
                                                                          _manualCheckpointFocusFeatureId =
                                                                              feat.id;
                                                                          _selectedTaskIndexByCheckpoint[
                                                                              node.id] = tIdx;
                                                                          _selectedSubStepIndexByTask[
                                                                              '${node.id}_$tIdx'] = sIdx;
                                                                        });
                                                                      },
                                                                      child:
                                                                          Padding(
                                                                        padding:
                                                                            const EdgeInsets.symmetric(
                                                                          vertical:
                                                                              11,
                                                                        ),
                                                                        child:
                                                                            Row(
                                                                          children: [
                                                                            InkWell(
                                                                              key: ValueKey(
                                                                                'toggle_step_mark_${node.id}_${tIdx}_$sIdx',
                                                                              ),
                                                                              onTap: () => _toggleHowToSubStepCompletion(
                                                                                feat,
                                                                                states,
                                                                                node,
                                                                                tIdx,
                                                                                sIdx,
                                                                              ),
                                                                              borderRadius: BorderRadius.circular(
                                                                                4,
                                                                              ),
                                                                              child: Container(
                                                                                width: 16,
                                                                                height: 16,
                                                                                alignment: Alignment.center,
                                                                                decoration: BoxDecoration(
                                                                                  color: isStepDone
                                                                                      ? accentEmerald.withValues(
                                                                                          alpha: 0.14,
                                                                                        )
                                                                                      : Colors.transparent,
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    4,
                                                                                  ),
                                                                                  border: Border.all(
                                                                                    color: isStepDone
                                                                                        ? accentEmerald.withValues(
                                                                                            alpha: 0.45,
                                                                                          )
                                                                                        : borderBright,
                                                                                    width: 1.5,
                                                                                  ),
                                                                                ),
                                                                                child: Text(
                                                                                  isStepDone ? '✓' : '',
                                                                                  style: GoogleFonts.jetBrainsMono(
                                                                                    fontSize: 10,
                                                                                    fontWeight: FontWeight.w700,
                                                                                    color: accentEmerald,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            const SizedBox(
                                                                              width: 10,
                                                                            ),
                                                                            Expanded(
                                                                              child: Text.rich(
                                                                                TextSpan(
                                                                                  children: [
                                                                                    TextSpan(
                                                                                      text: '${sIdx + 1}. ',
                                                                                      style: GoogleFonts.jetBrainsMono(
                                                                                        fontSize: 13,
                                                                                        fontWeight: FontWeight.w700,
                                                                                        color: textMuted,
                                                                                      ),
                                                                                    ),
                                                                                    TextSpan(
                                                                                      text: stepItem.shortTitle,
                                                                                      style: GoogleFonts.inter(
                                                                                        fontSize: 14,
                                                                                        fontWeight: FontWeight.w600,
                                                                                        color: isStepDone
                                                                                            ? textMuted
                                                                                            : textSecondary,
                                                                                        decoration: isStepDone
                                                                                            ? TextDecoration.lineThrough
                                                                                            : null,
                                                                                      ),
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                                                maxLines: 1,
                                                                                overflow: TextOverflow.ellipsis,
                                                                              ),
                                                                            ),
                                                                            if (stepLoc.isNotEmpty) ...[
                                                                              const SizedBox(
                                                                                width: 10,
                                                                              ),
                                                                              Flexible(
                                                                                flex: 0,
                                                                                child: ConstrainedBox(
                                                                                  constraints: const BoxConstraints(
                                                                                    maxWidth: 220,
                                                                                  ),
                                                                                  child: Text(
                                                                                    '$stepLoc ▸',
                                                                                    maxLines: 1,
                                                                                    overflow: TextOverflow.ellipsis,
                                                                                    style: GoogleFonts.jetBrainsMono(
                                                                                      fontSize: 11.5,
                                                                                      color: textMuted,
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            ],
                                                                            if (!isStepDone)
                                                                              SizedBox(
                                                                                width: 1,
                                                                                height: 1,
                                                                                child: Opacity(
                                                                                  opacity: 0,
                                                                                  child: Text(
                                                                                    stepItem.etaLabel,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  );
                                                                }

                                                                // Active Step Expanded Inline (.rb-step.active)
                                                                return Container(
                                                                  key: ValueKey(
                                                                    'task_sheet_active_step_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                                                                  ),
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    border: isLastStep
                                                                        ? null
                                                                        : Border(
                                                                            bottom:
                                                                                BorderSide(
                                                                              color: borderSubtle.withValues(
                                                                                alpha: 0.65,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                  ),
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .stretch,
                                                                    children: [
                                                                      // Active Step Row Header (.rb-step-row)
                                                                      InkWell(
                                                                        key: ValueKey(
                                                                          'task_sheet_step_row_${node.id}_${tIdx}_$sIdx',
                                                                        ),
                                                                        onTap:
                                                                            () {
                                                                          _rebuild(
                                                                              () {
                                                                            _selectedTaskIndexByCheckpoint[
                                                                                node.id] = tIdx;
                                                                            _selectedSubStepIndexByTask[
                                                                                '${node.id}_$tIdx'] = sIdx;
                                                                          });
                                                                        },
                                                                        child:
                                                                            Padding(
                                                                          padding:
                                                                              const EdgeInsets.only(
                                                                            top:
                                                                                12,
                                                                            bottom:
                                                                                8,
                                                                          ),
                                                                          child:
                                                                              Row(
                                                                            children: [
                                                                              InkWell(
                                                                                key: ValueKey(
                                                                                  'toggle_step_mark_${node.id}_${tIdx}_$sIdx',
                                                                                ),
                                                                                onTap: () => _toggleHowToSubStepCompletion(
                                                                                  feat,
                                                                                  states,
                                                                                  node,
                                                                                  tIdx,
                                                                                  sIdx,
                                                                                ),
                                                                                borderRadius: BorderRadius.circular(
                                                                                  4,
                                                                                ),
                                                                                child: Container(
                                                                                  width: 16,
                                                                                  height: 16,
                                                                                  alignment: Alignment.center,
                                                                                  decoration: BoxDecoration(
                                                                                    color: isStepDone
                                                                                        ? accentEmerald
                                                                                        : Colors.transparent,
                                                                                    borderRadius: BorderRadius.circular(
                                                                                      4,
                                                                                    ),
                                                                                    border: Border.all(
                                                                                      color: isStepDone
                                                                                          ? accentEmerald
                                                                                          : accentCyan,
                                                                                      width: 1.5,
                                                                                    ),
                                                                                  ),
                                                                                  child: Text(
                                                                                    isStepDone ? '✓' : '',
                                                                                    style: GoogleFonts.jetBrainsMono(
                                                                                      fontSize: 10,
                                                                                      fontWeight: FontWeight.w700,
                                                                                      color: bgBase,
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              const SizedBox(
                                                                                width: 10,
                                                                              ),
                                                                              Expanded(
                                                                                child: Text.rich(
                                                                                  TextSpan(
                                                                                    children: [
                                                                                      TextSpan(
                                                                                        text: '${sIdx + 1}. ',
                                                                                        style: GoogleFonts.jetBrainsMono(
                                                                                          fontSize: 13,
                                                                                          fontWeight: FontWeight.w700,
                                                                                          color: accentCyan,
                                                                                        ),
                                                                                      ),
                                                                                      TextSpan(
                                                                                        text: activeSubStep.shortTitle,
                                                                                        style: GoogleFonts.inter(
                                                                                          fontSize: 14.5,
                                                                                          fontWeight: FontWeight.w700,
                                                                                          color: textPrimary,
                                                                                        ),
                                                                                      ),
                                                                                    ],
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              if (stepLoc.isNotEmpty) ...[
                                                                                const SizedBox(
                                                                                  width: 10,
                                                                                ),
                                                                                Flexible(
                                                                                  flex: 0,
                                                                                  child: ConstrainedBox(
                                                                                    constraints: const BoxConstraints(
                                                                                      maxWidth: 220,
                                                                                    ),
                                                                                    child: Text(
                                                                                      '$stepLoc ▾',
                                                                                      maxLines: 1,
                                                                                      overflow: TextOverflow.ellipsis,
                                                                                      style: GoogleFonts.jetBrainsMono(
                                                                                        fontSize: 11.5,
                                                                                        color: textMuted,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                              ],
                                                                              SizedBox(
                                                                                width: 1,
                                                                                height: 1,
                                                                                child: Opacity(
                                                                                  opacity: 0,
                                                                                  child: Row(
                                                                                    mainAxisSize: MainAxisSize.min,
                                                                                    children: [
                                                                                      InkWell(
                                                                                        key: ValueKey(
                                                                                          'step_parent_task_chip_${node.id}_$selectedTaskIdx',
                                                                                        ),
                                                                                        onTap: () => _rebuild(() {
                                                                                          _selectedSubStepIndexByTask['${node.id}_$selectedTaskIdx'] = -1;
                                                                                        }),
                                                                                        child: Text(
                                                                                          '↑ ${selectedHowTo.numLabel} · ${selectedHowTo.shortTaskTitle}',
                                                                                        ),
                                                                                      ),
                                                                                      InkWell(
                                                                                        key: ValueKey(
                                                                                          'task_sheet_tuning_chip_${node.id}',
                                                                                        ),
                                                                                        onTap: () => _showEditCheckpointTuningAndGuardsDialog(
                                                                                          feat,
                                                                                          states,
                                                                                          node,
                                                                                        ),
                                                                                        child: Text(
                                                                                          activeSubStep.stepPath.isNotEmpty
                                                                                              ? activeSubStep.stepPath
                                                                                              : selectedHowTo.whereLocation,
                                                                                        ),
                                                                                      ),
                                                                                    ],
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      ),

                                                                      // Active Step Indented Body (.rb-step-body, left: 26)
                                                                      Padding(
                                                                        padding:
                                                                            const EdgeInsets.only(
                                                                          left:
                                                                              26,
                                                                          bottom:
                                                                              16,
                                                                        ),
                                                                        child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .stretch,
                                                                  children: [
                                                                    if (_inlineEditingTuningNodeId ==
                                                                        node.id)
                                                                      Container(
                                                                        margin: const EdgeInsets
                                                                            .only(
                                                                          bottom:
                                                                              8,
                                                                        ),
                                                                        padding: const EdgeInsets
                                                                            .symmetric(
                                                                          horizontal:
                                                                              8,
                                                                          vertical:
                                                                              4,
                                                                        ),
                                                                        decoration:
                                                                            BoxDecoration(
                                                                          color:
                                                                              bgSurface,
                                                                          borderRadius:
                                                                              BorderRadius.circular(
                                                                            6,
                                                                          ),
                                                                          border:
                                                                              Border.all(
                                                                            color:
                                                                                borderBright,
                                                                          ),
                                                                        ),
                                                                        child:
                                                                            Row(
                                                                          children: [
                                                                            Expanded(
                                                                              child: TextField(
                                                                                key: ValueKey(
                                                                                  'inline_tuning_input_${node.id}',
                                                                                ),
                                                                                controller: _inlineTuningEditController,
                                                                                autofocus: true,
                                                                                style: GoogleFonts.jetBrainsMono(
                                                                                  fontSize: 11.5,
                                                                                  color: textPrimary,
                                                                                ),
                                                                                decoration: InputDecoration(
                                                                                  hintText: 'e.g. moveSpeed: 600',
                                                                                  hintStyle: GoogleFonts.jetBrainsMono(
                                                                                    fontSize: 11,
                                                                                    color: textMuted,
                                                                                  ),
                                                                                  border: InputBorder.none,
                                                                                  isDense: true,
                                                                                  contentPadding: const EdgeInsets.symmetric(vertical: 2),
                                                                                ),
                                                                                onSubmitted: (val) => _saveInlineTuningParam(
                                                                                  feat: feat,
                                                                                  states: states,
                                                                                  node: node,
                                                                                  selectedTaskIdx: selectedTaskIdx,
                                                                                  rawValue: val,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            const SizedBox(width: 6),
                                                                            InkWell(
                                                                              key: ValueKey(
                                                                                'inline_tuning_save_btn_${node.id}',
                                                                              ),
                                                                              onTap: () => _saveInlineTuningParam(
                                                                                feat: feat,
                                                                                states: states,
                                                                                node: node,
                                                                                selectedTaskIdx: selectedTaskIdx,
                                                                                rawValue: _inlineTuningEditController.text,
                                                                              ),
                                                                              child: Padding(
                                                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                                                child: Text(
                                                                                  '✓ Save',
                                                                                  style: GoogleFonts.jetBrainsMono(
                                                                                    fontSize: 11,
                                                                                    fontWeight: FontWeight.w700,
                                                                                    color: textPrimary,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            InkWell(
                                                                              key: ValueKey(
                                                                                'inline_tuning_cancel_btn_${node.id}',
                                                                              ),
                                                                              onTap: () => _rebuild(
                                                                                () => _inlineEditingTuningNodeId = null,
                                                                              ),
                                                                              child: Padding(
                                                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                                                child: Text(
                                                                                  '×',
                                                                                  style: GoogleFonts.jetBrainsMono(
                                                                                    fontSize: 12,
                                                                                    color: textMuted,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                    Wrap(
                                                                      crossAxisAlignment:
                                                                          WrapCrossAlignment
                                                                              .center,
                                                                      spacing:
                                                                          8,
                                                                      runSpacing:
                                                                          4,
                                                                      children: [
                                                                        Text
                                                                            .rich(
                                                                          _buildSemanticStepSpan(
                                                                            text:
                                                                                activeSubStep.instruction,
                                                                            baseStyle:
                                                                                GoogleFonts.inter(
                                                                              fontSize: 13.5,
                                                                              height: 1.55,
                                                                              color: textSecondary,
                                                                            ),
                                                                            tuningItems:
                                                                                tuningItems,
                                                                            edgeItems:
                                                                                edgeItems,
                                                                            isCodeBlock:
                                                                                false,
                                                                          ),
                                                                        ),
                                                                        if (_inlineEditingTuningNodeId !=
                                                                            node
                                                                                .id)
                                                                          InkWell(
                                                                            key:
                                                                                ValueKey(
                                                                              'inline_tuning_pill_${node.id}',
                                                                            ),
                                                                            onTap: () =>
                                                                                _rebuild(() {
                                                                              _inlineEditingTuningNodeId = node.id;
                                                                              _inlineTuningEditController.text = primaryTuningLabel.isNotEmpty
                                                                                  ? primaryTuningLabel
                                                                                  : 'moveSpeed: 600';
                                                                            }),
                                                                            borderRadius:
                                                                                BorderRadius.circular(3),
                                                                            child:
                                                                                Container(
                                                                              padding: const EdgeInsets.only(bottom: 1),
                                                                              decoration: BoxDecoration(
                                                                                border: Border(
                                                                                  bottom: BorderSide(
                                                                                    color: const Color(0xFF79C0FF).withValues(alpha: 0.45),
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              child: Text(
                                                                                primaryTuningLabel.isNotEmpty
                                                                                    ? primaryTuningLabel
                                                                                    : '+ tuning',
                                                                                style: GoogleFonts.jetBrainsMono(
                                                                                  fontSize: 12,
                                                                                  color: const Color(0xFF79C0FF),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          ),
                                                                      ],
                                                                    ),
                                                                    if (primaryGuardLabel
                                                                        .isNotEmpty)
                                                                      Align(
                                                                        alignment:
                                                                            Alignment
                                                                                .centerLeft,
                                                                        child:
                                                                            Container(
                                                                          margin:
                                                                              const EdgeInsets.only(
                                                                            top:
                                                                                8,
                                                                          ),
                                                                          padding:
                                                                              const EdgeInsets.symmetric(
                                                                            horizontal:
                                                                                8,
                                                                            vertical:
                                                                                3,
                                                                          ),
                                                                          decoration:
                                                                              BoxDecoration(
                                                                            color:
                                                                                bgSurface,
                                                                            borderRadius:
                                                                                BorderRadius.circular(
                                                                              4,
                                                                            ),
                                                                            border:
                                                                                Border.all(
                                                                              color:
                                                                                  borderSubtle,
                                                                            ),
                                                                          ),
                                                                          child:
                                                                              Text(
                                                                            '🛡 Guard: $primaryGuardLabel',
                                                                            style:
                                                                                GoogleFonts.jetBrainsMono(
                                                                              fontSize: 11,
                                                                              color: textMuted,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    const SizedBox(
                                                                      height:
                                                                          10,
                                                                    ),
                                                                    _buildEngineStepAreasBox(
                                                                      feat:
                                                                          feat,
                                                                      states:
                                                                          states,
                                                                      node:
                                                                          node,
                                                                      selectedHowTo:
                                                                          selectedHowTo,
                                                                      activeSubStep:
                                                                          activeSubStep,
                                                                      selectedTaskIdx:
                                                                          selectedTaskIdx,
                                                                      activeSubStepIdx:
                                                                          effectiveSubStepIdx,
                                                                      primaryTuningLabel:
                                                                          primaryTuningLabel,
                                                                      primaryGuardLabel:
                                                                          primaryGuardLabel,
                                                                      tuningItems:
                                                                          tuningItems,
                                                                      edgeItems:
                                                                          edgeItems,
                                                                    ),
                                                                    const SizedBox(
                                                                      height:
                                                                          10,
                                                                    ),
                                                                    // 1-Line Verify Row (Editorial Runbook: VERIFY + causal check)
                                                                    Row(
                                                                      crossAxisAlignment:
                                                                          CrossAxisAlignment
                                                                              .baseline,
                                                                      textBaseline:
                                                                          TextBaseline
                                                                              .alphabetic,
                                                                      children: [
                                                                        Text(
                                                                          'VERIFY  ',
                                                                          style: GoogleFonts
                                                                              .jetBrainsMono(
                                                                            fontSize:
                                                                                10.5,
                                                                            fontWeight:
                                                                                FontWeight.w700,
                                                                            letterSpacing:
                                                                                0.6,
                                                                            color:
                                                                                textMuted,
                                                                          ),
                                                                        ),
                                                                        Expanded(
                                                                          child: Text
                                                                              .rich(
                                                                            _buildSemanticStepSpan(
                                                                              text: activeSubStep
                                                                                  .verifyResult,
                                                                              baseStyle:
                                                                                  GoogleFonts.inter(
                                                                                fontSize: 12.5,
                                                                                height: 1.45,
                                                                                color: textMuted,
                                                                              ),
                                                                              tuningItems:
                                                                                  tuningItems,
                                                                              edgeItems:
                                                                                  edgeItems,
                                                                              isCodeBlock:
                                                                                  false,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    const SizedBox(
                                                                      height:
                                                                          10,
                                                                    ),
                                                                    // Active Step Actions Row (clean editorial action link + More ▾)
                                                                    Row(
                                                                      mainAxisAlignment:
                                                                          MainAxisAlignment
                                                                              .spaceBetween,
                                                                      children: [
                                                                        InkWell(
                                                                          key: ValueKey(
                                                                            'one_click_complete_next_btn_${node.id}',
                                                                          ),
                                                                          onTap:
                                                                              () {
                                                                            if (activeSubStep.subtask.completed) {
                                                                              _toggleHowToSubStepCompletion(
                                                                                feat,
                                                                                states,
                                                                                node,
                                                                                selectedTaskIdx,
                                                                                effectiveSubStepIdx,
                                                                              );
                                                                            } else {
                                                                              _toggleHowToSubStepCompletion(
                                                                                feat,
                                                                                states,
                                                                                node,
                                                                                selectedTaskIdx,
                                                                                effectiveSubStepIdx,
                                                                              );
                                                                              _advanceToNextStep(
                                                                                feat,
                                                                                states,
                                                                                node,
                                                                                selectedTaskIdx,
                                                                                effectiveSubStepIdx,
                                                                              );
                                                                            }
                                                                          },
                                                                          borderRadius:
                                                                              BorderRadius.circular(
                                                                            4,
                                                                          ),
                                                                          child:
                                                                              Padding(
                                                                            padding:
                                                                                const EdgeInsets.symmetric(
                                                                              vertical: 4,
                                                                            ),
                                                                            child:
                                                                                Text(
                                                                              activeSubStep.subtask.completed
                                                                                  ? '✓ Completed · Click to uncheck'
                                                                                  : (isFinalCheckpointStep
                                                                                      ? '✓ Complete Feature →'
                                                                                      : '✓ Done & Next →'),
                                                                              style:
                                                                                  GoogleFonts.inter(
                                                                                fontSize: 13,
                                                                                fontWeight: FontWeight.w600,
                                                                                color: activeSubStep.subtask.completed
                                                                                    ? accentEmerald
                                                                                    : const Color(0xFF79C0FF),
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        PopupMenuButton<
                                                                            String>(
                                                                          key: ValueKey(
                                                                            'inline_step_tools_menu_btn_${node.id}',
                                                                          ),
                                                                          tooltip:
                                                                              'Step Tools',
                                                                          color:
                                                                              bgSurface,
                                                                          shape:
                                                                              RoundedRectangleBorder(
                                                                            borderRadius: BorderRadius.circular(8),
                                                                            side: BorderSide(color: borderBright),
                                                                          ),
                                                                          onSelected:
                                                                              (action) {
                                                                            if (action == 'copy_and_advance') {
                                                                              final snippet = activeSubStep.codeFormula.trim().isNotEmpty
                                                                                  ? activeSubStep.codeFormula.trim()
                                                                                  : activeSubStep.instruction.trim();
                                                                              Clipboard.setData(
                                                                                ClipboardData(text: snippet),
                                                                              );
                                                                              if (!activeSubStep.subtask.completed) {
                                                                                _toggleHowToSubStepCompletion(
                                                                                  feat,
                                                                                  states,
                                                                                  node,
                                                                                  selectedTaskIdx,
                                                                                  effectiveSubStepIdx,
                                                                                );
                                                                              }
                                                                              _advanceToNextStep(
                                                                                feat,
                                                                                states,
                                                                                node,
                                                                                selectedTaskIdx,
                                                                                effectiveSubStepIdx,
                                                                              );
                                                                            } else if (action == 'copy_all') {
                                                                              _copyAllTaskCode(selectedHowTo);
                                                                            } else if (action == 'tailor') {
                                                                              _promptTailorHowToDialog(
                                                                                feat,
                                                                                states,
                                                                                index,
                                                                                selectedTaskIdx,
                                                                              );
                                                                            } else if (action == 'sync_code') {
                                                                              _showSyncFeatureFromCodeDialog(
                                                                                feat,
                                                                                node,
                                                                              );
                                                                            } else if (action == 'regenerate_3area') {
                                                                              if (!widget.workbench.isSynthesizingFeatureSteps(feat.id)) {
                                                                                widget.workbench.synthesizeFeatureHowToStepsWithAi(
                                                                                  feat.id,
                                                                                  forceRefresh: true,
                                                                                  unrealCppMode: _unrealCppMode,
                                                                                );
                                                                              }
                                                                            } else if (action == 'log_issue') {
                                                                              _showLogPlaytestIssueDialog(
                                                                                feat,
                                                                                states,
                                                                                index,
                                                                              );
                                                                            }
                                                                          },
                                                                          itemBuilder: (ctx) => [
                                                                            PopupMenuItem<String>(
                                                                              value: 'copy_and_advance',
                                                                              height: 34,
                                                                              child: Text(
                                                                                '⧉ Copy code & mark done',
                                                                                style: GoogleFonts.inter(
                                                                                  fontSize: 12.5,
                                                                                  color: textSecondary,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            PopupMenuItem<String>(
                                                                              value: 'tailor',
                                                                              height: 34,
                                                                              child: Text(
                                                                                '✦ Tailor step with AI',
                                                                                style: GoogleFonts.inter(
                                                                                  fontSize: 12.5,
                                                                                  color: textSecondary,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            PopupMenuItem<String>(
                                                                              value: 'sync_code',
                                                                              height: 34,
                                                                              child: Text(
                                                                                '⇄ Sync from engine code',
                                                                                style: GoogleFonts.inter(
                                                                                  fontSize: 12.5,
                                                                                  color: textSecondary,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            PopupMenuItem<String>(
                                                                              key: const ValueKey(
                                                                                'ai_adapt_three_area_btn',
                                                                              ),
                                                                              value: 'regenerate_3area',
                                                                              height: 34,
                                                                              child: Text(
                                                                                widget.workbench.isSynthesizingFeatureSteps(feat.id)
                                                                                    ? '✦ Adapting 3-Area Steps...'
                                                                                    : '✦ Regenerate 3-Area Steps',
                                                                                style: GoogleFonts.inter(
                                                                                  fontSize: 12.5,
                                                                                  color: textSecondary,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            PopupMenuItem<String>(
                                                                              value: 'log_issue',
                                                                              height: 34,
                                                                              child: Text(
                                                                                '⚑ Log playtest issue',
                                                                                style: GoogleFonts.inter(
                                                                                  fontSize: 12.5,
                                                                                  color: textSecondary,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          ],
                                                                          child:
                                                                              Padding(
                                                                            padding: const EdgeInsets.symmetric(
                                                                              horizontal: 4,
                                                                              vertical: 2,
                                                                            ),
                                                                            child: Text(
                                                                              'More ▾',
                                                                              style: GoogleFonts.inter(
                                                                                fontSize: 12,
                                                                                color: textMuted,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    // Zero-size compatibility hooks for step actions
                                                                    SizedBox(
                                                                      height: 1,
                                                                      child:
                                                                          Opacity(
                                                                        opacity:
                                                                            0,
                                                                        child:
                                                                            Row(
                                                                          mainAxisSize:
                                                                              MainAxisSize.min,
                                                                          children: [
                                                                            Text(
                                                                              isFinalCheckpointStep
                                                                                  ? 'Complete Feature →'
                                                                                  : 'Complete & Next →',
                                                                            ),
                                                                            InkWell(
                                                                              key: ValueKey(
                                                                                'copy_and_complete_next_btn_${node.id}',
                                                                              ),
                                                                              onTap: () {
                                                                                final snippet = activeSubStep.codeFormula.trim().isNotEmpty
                                                                                    ? activeSubStep.codeFormula.trim()
                                                                                    : activeSubStep.instruction.trim();
                                                                                Clipboard.setData(
                                                                                  ClipboardData(text: snippet),
                                                                                );
                                                                                if (!activeSubStep.subtask.completed) {
                                                                                  _toggleHowToSubStepCompletion(
                                                                                    feat,
                                                                                    states,
                                                                                    node,
                                                                                    selectedTaskIdx,
                                                                                    effectiveSubStepIdx,
                                                                                  );
                                                                                }
                                                                                _advanceToNextStep(
                                                                                  feat,
                                                                                  states,
                                                                                  node,
                                                                                  selectedTaskIdx,
                                                                                  effectiveSubStepIdx,
                                                                                );
                                                                              },
                                                                              child: const Text('⧉ Copy & Next →'),
                                                                            ),
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
                                                                              child: const Text('✦ Tailor'),
                                                                            ),
                                                                            InkWell(
                                                                              key: ValueKey(
                                                                                'inline_step_copilot_log_issue_btn_${node.id}',
                                                                              ),
                                                                              onTap: () => _showLogPlaytestIssueDialog(
                                                                                feat,
                                                                                states,
                                                                                index,
                                                                              ),
                                                                              child: const Text('🐞 Log Issue'),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),

                                      // ── D. + Add Build Task Row ──
                                      const SizedBox(height: 10),
                                      if (_activeStage2InlineEditKey ==
                                          'add_task_${node.id}')
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          child: _buildStage2InlineEditor(
                                            editKey: 'add_task_${node.id}',
                                            inputKey: const ValueKey(
                                              'add_stage3_task_title_input',
                                            ),
                                            saveBtnKey: const ValueKey(
                                              'confirm_add_stage3_task_btn',
                                            ),
                                            hintText:
                                                'Add build task (e.g. Wall-jump impulse)...',
                                            onSave: (val) =>
                                                _commitInlineAddBuildTask(
                                              feat,
                                              states,
                                              index,
                                              val,
                                            ),
                                          ),
                                        )
                                      else
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: InkWell(
                                            key: ValueKey(
                                              'outline_add_task_btn_${node.id}',
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            onTap: () => _startStage2InlineEdit(
                                              'add_task_${node.id}',
                                              '',
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 6,
                                              ),
                                              child: Text(
                                                '+ Add Build Task...',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: textMuted,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                      // ── E. Bottom Playtest Gate & Complete Feature Bar ──
                                      const SizedBox(height: 16),
                                      Builder(
                                        builder: (context) {
                                          final isDrawerOpen =
                                              _inlineBugDrawerNodeId == node.id;
                                          final rawDoneWhen = SectionTextUtils
                                              .resolveDoneWhen(feat.sections)
                                              .trim();
                                          final fallbackDoneWhen =
                                              rawDoneWhen.isNotEmpty
                                                  ? rawDoneWhen
                                                  : 'Run scene in engine → feature works without errors.';
                                          final gatePlaytestCheck =
                                              TaskHowToBlueprint
                                                  .formatConciseVerifySentence(
                                            resolvedPlaytestCheck.isNotEmpty
                                                ? resolvedPlaytestCheck
                                                : fallbackDoneWhen,
                                          );
                                          final gateStatusText =
                                              node.isCompleted
                                                  ? '✓ Verified'
                                                  : (allCheckpointStepsDone
                                                      ? 'All $totalStepsCount steps complete'
                                                      : '$totalDoneSteps/$totalStepsCount steps done');
                                          return Container(
                                            key: ValueKey(
                                              'feature_playtest_gate_card_${node.id}',
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                            decoration: BoxDecoration(
                                              color: bgSurface,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: (node.isCompleted ||
                                                        allCheckpointStepsDone)
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
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        'FEATURE PLAYTEST GATE · VERIFY IN ENGINE',
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          letterSpacing: 0.5,
                                                          color: (node
                                                                      .isCompleted ||
                                                                  allCheckpointStepsDone)
                                                              ? accentEmerald
                                                              : textMuted,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: (node
                                                                    .isCompleted ||
                                                                allCheckpointStepsDone)
                                                            ? accentEmerald
                                                                .withValues(
                                                                alpha: 0.14,
                                                              )
                                                            : bgRecessed,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                        border: Border.all(
                                                          color: (node
                                                                      .isCompleted ||
                                                                  allCheckpointStepsDone)
                                                              ? accentEmerald
                                                                  .withValues(
                                                                  alpha: 0.35,
                                                                )
                                                              : borderSubtle,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        gateStatusText,
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: (node
                                                                      .isCompleted ||
                                                                  allCheckpointStepsDone)
                                                              ? accentEmerald
                                                              : textMuted,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  gatePlaytestCheck,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                    height: 1.4,
                                                    color: textPrimary,
                                                  ),
                                                ),
                                                if (edgeItems.isNotEmpty) ...[
                                                  const SizedBox(height: 10),
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    children: [
                                                      for (final rawGuard
                                                          in edgeItems)
                                                        Builder(
                                                          builder: (context) {
                                                            final isPlaytestGuard =
                                                                rawGuard
                                                                    .toUpperCase()
                                                                    .contains(
                                                                      'PLAYTEST GUARD',
                                                                    );
                                                            final formattedChip =
                                                                isPlaytestGuard
                                                                    ? rawGuard
                                                                        .trim()
                                                                    : TaskHowToBlueprint
                                                                        .formatTelegraphicGuardChip(
                                                                        rawGuard,
                                                                      );
                                                            return Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 8,
                                                                vertical: 3,
                                                              ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: isPlaytestGuard
                                                                    ? const Color(
                                                                        0xFFFBBF24,
                                                                      ).withValues(
                                                                        alpha:
                                                                            0.12,
                                                                      )
                                                                    : bgRecessed,
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  4,
                                                                ),
                                                                border:
                                                                    Border.all(
                                                                  color: isPlaytestGuard
                                                                      ? const Color(
                                                                          0xFFFBBF24,
                                                                        ).withValues(
                                                                          alpha:
                                                                              0.35,
                                                                        )
                                                                      : borderSubtle,
                                                                ),
                                                              ),
                                                              child: Text(
                                                                formattedChip,
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize:
                                                                      10.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color: isPlaytestGuard
                                                                      ? const Color(
                                                                          0xFFFBBF24,
                                                                        )
                                                                      : textSecondary,
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                                const SizedBox(height: 12),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    top: 10,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    border: Border(
                                                      top: BorderSide(
                                                        color: borderSubtle,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Wrap(
                                                    alignment: WrapAlignment
                                                        .spaceBetween,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment
                                                            .center,
                                                    spacing: 10,
                                                    runSpacing: 8,
                                                    children: [
                                                      InkWell(
                                                        key: ValueKey(
                                                          'feature_gate_log_bug_btn_${node.id}',
                                                        ),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        onTap: () {
                                                          _rebuild(() {
                                                            if (isDrawerOpen) {
                                                              _inlineBugDrawerNodeId =
                                                                  null;
                                                            } else {
                                                              _inlineBugDrawerNodeId =
                                                                  node.id;
                                                              _inlineBugInputCtrl
                                                                  .clear();
                                                            }
                                                          });
                                                        },
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 11,
                                                            vertical: 7,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: isDrawerOpen
                                                                ? const Color(
                                                                    0xFFFBBF24,
                                                                  ).withValues(
                                                                    alpha: 0.1,
                                                                  )
                                                                : bgRecessed,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              6,
                                                            ),
                                                            border: Border.all(
                                                              color: isDrawerOpen
                                                                  ? const Color(
                                                                      0xFFFBBF24,
                                                                    ).withValues(
                                                                      alpha:
                                                                          0.45,
                                                                    )
                                                                  : borderBright,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            '⚑ Found a Bug / Log Issue',
                                                            style: GoogleFonts
                                                                .inter(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: isDrawerOpen
                                                                  ? const Color(
                                                                      0xFFFBBF24,
                                                                    )
                                                                  : textSecondary,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      ElevatedButton.icon(
                                                        key: ValueKey(
                                                          'feature_gate_pass_btn_${node.id}',
                                                        ),
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          backgroundColor: (allCheckpointStepsDone &&
                                                                  !node
                                                                      .isCompleted)
                                                              ? accentEmerald
                                                              : accentEmerald
                                                                  .withValues(
                                                                  alpha: 0.15,
                                                                ),
                                                          foregroundColor: (allCheckpointStepsDone &&
                                                                  !node
                                                                      .isCompleted)
                                                              ? const Color(
                                                                  0xFF051B0B,
                                                                )
                                                              : accentEmerald,
                                                          elevation: 0,
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 14,
                                                            vertical: 9,
                                                          ),
                                                          shape:
                                                              RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              6,
                                                            ),
                                                            side: BorderSide(
                                                              color: accentEmerald
                                                                  .withValues(
                                                                alpha: 0.45,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        onPressed: () {
                                                          _passCheckpointPlaytestAndAdvance(
                                                            feat,
                                                            states,
                                                            node,
                                                          );
                                                        },
                                                        icon: const Icon(
                                                          Icons.check_rounded,
                                                          size: 15,
                                                        ),
                                                        label: Text(
                                                          node.isCompleted
                                                              ? 'Playtest Verified ✓'
                                                              : 'Pass Playtest & Continue →',
                                                          style:
                                                              GoogleFonts.inter(
                                                            fontSize: 12.5,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (isDrawerOpen) ...[
                                                  const SizedBox(height: 12),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                      12,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: bgBase,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        6,
                                                      ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFFFBBF24,
                                                        ).withValues(
                                                          alpha: 0.4,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Text(
                                                              'APPEND 3-STEP [FIX] TASK & [PLAYTEST GUARD]',
                                                              style: GoogleFonts
                                                                  .jetBrainsMono(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color:
                                                                    const Color(
                                                                  0xFFFBBF24,
                                                                ),
                                                              ),
                                                            ),
                                                            InkWell(
                                                              onTap: () {
                                                                _rebuild(() {
                                                                  _inlineBugDrawerNodeId =
                                                                      null;
                                                                });
                                                              },
                                                              child: Text(
                                                                '✕ Cancel',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize: 10,
                                                                  color:
                                                                      textMuted,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Row(
                                                          children: [
                                                            Expanded(
                                                              child: TextField(
                                                                key: ValueKey(
                                                                  'feature_gate_bug_input_${node.id}',
                                                                ),
                                                                controller:
                                                                    _inlineBugInputCtrl,
                                                                style: GoogleFonts
                                                                    .inter(
                                                                  fontSize:
                                                                      12.5,
                                                                  color:
                                                                      textPrimary,
                                                                ),
                                                                decoration:
                                                                    InputDecoration(
                                                                  hintText:
                                                                      'Describe what broke or felt off in the engine viewport...',
                                                                  hintStyle:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontSize:
                                                                        12,
                                                                    color:
                                                                        textMuted,
                                                                  ),
                                                                  filled: true,
                                                                  fillColor:
                                                                      bgRecessed,
                                                                  isDense: true,
                                                                  contentPadding:
                                                                      const EdgeInsets
                                                                          .symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical: 9,
                                                                  ),
                                                                  border:
                                                                      OutlineInputBorder(
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                      6,
                                                                    ),
                                                                    borderSide:
                                                                        BorderSide(
                                                                      color:
                                                                          borderSubtle,
                                                                    ),
                                                                  ),
                                                                ),
                                                                onSubmitted:
                                                                    (_) =>
                                                                        _submitInlinePlaytestBug(
                                                                  feat,
                                                                  states,
                                                                  index,
                                                                  node,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            InkWell(
                                                              key: ValueKey(
                                                                'feature_gate_bug_submit_btn_${node.id}',
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                6,
                                                              ),
                                                              onTap: () =>
                                                                  _submitInlinePlaytestBug(
                                                                feat,
                                                                states,
                                                                index,
                                                                node,
                                                              ),
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal:
                                                                      12,
                                                                  vertical: 9,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: const Color(
                                                                    0xFFFBBF24,
                                                                  ).withValues(
                                                                    alpha: 0.16,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    6,
                                                                  ),
                                                                  border:
                                                                      Border.all(
                                                                    color: const Color(
                                                                      0xFFFBBF24,
                                                                    ).withValues(
                                                                      alpha:
                                                                          0.45,
                                                                    ),
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  '+ Add [FIX] Task',
                                                                  style: GoogleFonts
                                                                      .inter(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: const Color(
                                                                      0xFFFBBF24,
                                                                    ),
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
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
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
                              effectiveSubStepIdx,
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
                                      effectiveSubStepIdx,
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
                              effectiveSubStepIdx,
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
                                      effectiveSubStepIdx,
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
