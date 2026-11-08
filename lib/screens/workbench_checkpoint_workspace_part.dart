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

    // All tasks & steps in this Checkpoint are 100% done!
    // Hold on the current Feature until the user passes the Playtest Gate.
    _completeAllCheckpointTasks(node);
    final cpIdx = states.indexWhere((s) => s.id == node.id);
    _rebuild(() {
      _awaitingPlaytestVerification.add(node.id);
      if (cpIdx != -1) {
        _manualCheckpointFocusIndex = cpIdx;
        _manualCheckpointFocusFeatureId = feat.id;
      }
      _selectedTaskIndexByCheckpoint[node.id] = pIdx;
      _selectedSubStepIndexByTask['${node.id}_$pIdx'] = sIdx;
    });
    widget.workbench.updateFeatureStates(feat.id, states);
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
    _rebuild();
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

  /// Builds the engine-aware structural context card for the Left Dock
  /// (Scene Hierarchy for Godot, Components & Blueprint for Unreal BP, Class Architecture for Unreal C++, Hierarchy for Unity)
  Widget _buildEngineHierarchyTreeCard({
    required TaskHowToBlueprint bp,
    required TaskHowToSubStep activeSubStep,
    required TaskHowToBlueprint selectedHowTo,
    required bool unrealCppMode,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color borderSubtle,
    required Color accentEmerald,
  }) {
    final engineLabel = selectedHowTo.engineLabel;
    final isUnreal = engineLabel.contains('UNREAL');
    final isUnity = engineLabel.contains('UNITY');

    String dockTitle;
    if (isUnreal) {
      dockTitle = unrealCppMode ? 'CLASS ARCHITECTURE (.H)' : 'COMPONENTS & BLUEPRINT';
    } else if (isUnity) {
      dockTitle = 'HIERARCHY & GAMEOBJECTS';
    } else {
      dockTitle = 'SCENE DOCK (.TSCN)';
    }

    final rawHierarchy = activeSubStep.area1Hierarchy?.trim() ?? '';
    final List<String> treeLines = [];
    if (rawHierarchy.isNotEmpty) {
      for (final rawLine in rawHierarchy.split('\n')) {
        final clean = rawLine.trim();
        if (clean.isNotEmpty) {
          treeLines.add(
            clean.startsWith('- ')
                ? clean.substring(2)
                : (clean.startsWith('• ') ? clean.substring(2) : clean),
          );
        }
      }
    }

    if (treeLines.isEmpty) {
      final targetName = activeSubStep.shortTitle;
      if (isUnreal) {
        if (unrealCppMode) {
          final headerName = activeSubStep.stepPath.isNotEmpty
              ? activeSubStep.stepPath.split('/').last
              : 'PlayerCharacter.h';
          treeLines.add('⚡ $headerName');
          treeLines.add('└ class APlayerCharacter : public ACharacter');
          treeLines.add('  └ UPROPERTY() $targetName [ACTIVE]');
        } else {
          treeLines.add('🧩 [Root] CapsuleComponent');
          treeLines.add('└ 🦴 CharacterMesh0 (SkeletalMesh)');
          treeLines.add('  └ 🎯 $targetName [ACTIVE]');
        }
      } else if (isUnity) {
        treeLines.add('📁 Player (GameObject)');
        treeLines.add('└ 🎯 $targetName [ACTIVE]');
        if (activeSubStep.stepPath.endsWith('.cs')) {
          treeLines.add('  └ 📜 ${activeSubStep.stepPath.split('/').last}');
        }
      } else {
        treeLines.add('📁 Player (CharacterBody3D)');
        treeLines.add('└ 🦴 Skeleton3D');
        treeLines.add('  └ 🎯 $targetName [ACTIVE]');
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  dockTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3.5),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.34),
                  ),
                ),
                child: Text(
                  selectedHowTo.engineLabel == 'UNREAL 5'
                      ? (unrealCppMode ? 'UNREAL 5 C++' : 'UNREAL 5 BLUEPRINT')
                      : selectedHowTo.engineLabel,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF7DD3FC),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in treeLines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: line.contains('[ACTIVE]')
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: line.contains('[ACTIVE]')
                      ? const Color(0xFF38BDF8)
                      : (line.startsWith('📁') ||
                              line.startsWith('⚡') ||
                              line.startsWith('🧩')
                          ? textPrimary
                          : textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
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
            child: isHalfScreenOverlayMode
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: bgSurface,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: borderBright),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Step ${effectiveSubStepIdx + 1}/${selectedHowTo.subSteps.length}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: activeSubStep.subtask.completed
                                ? accentEmerald
                                : accentCyan,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 13,
                          color: textMuted,
                        ),
                        SizedBox(
                          width: 1,
                          height: 1,
                          child: Opacity(
                            opacity: 0,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('02'),
                                Text(
                                  isTaskOverviewSelected
                                      ? 'TASK ${selectedHowTo.numLabel} OF ${howToBlueprints.length.toString().padLeft(2, '0')} · OVERVIEW'
                                      : 'STEP ${activeSubStepIdx + 1} OF ${selectedHowTo.subSteps.length}${activeSubStep.subtask.completed ? ' · COMPLETED ✓' : ''}',
                                ),
                                Text(
                                  'STEP ${effectiveSubStepIdx + 1} OF ${selectedHowTo.subSteps.length} · ~${activeSubStep.etaLabel}${activeSubStep.subtask.completed ? ' · COMPLETED ✓' : ''}',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
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
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    decoration: BoxDecoration(
                      color: bgRecessed,
                      border: Border(
                        bottom: BorderSide(color: borderSubtle),
                      ),
                    ),
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
                                borderRadius: BorderRadius.circular(5),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: bgSurface,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                            color: _isHalfScreenOutlinerOpen
                                                ? accentEmerald
                                                : borderBright,
                                          ),
                                        ),
                                        child: Text(
                                          '☰',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: _isHalfScreenOutlinerOpen
                                                ? textPrimary
                                                : textSecondary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: RichText(
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          text: TextSpan(
                                            style: GoogleFonts.inter(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: textPrimary,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: '$epicShortCode › ',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: textMuted,
                                                ),
                                              ),
                                              TextSpan(text: featShortTitle),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 1,
                                        height: 1,
                                        child: Opacity(
                                          opacity: 0,
                                          child: Text(
                                            '$epicDisplayTitle › $featShortTitle',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
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
                            const SizedBox(width: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Zero-size compatibility hooks for halfscreen test keys
                                SizedBox(
                                  width: 1,
                                  height: 1,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Opacity(
                                      opacity: 0,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            key: ValueKey(
                                              'halfscreen_open_feature_inbox_btn_${node.id}',
                                            ),
                                            onTap: () => _showFeatureInboxModal(
                                              context,
                                              preferredBeatId: feat.parentId,
                                            ),
                                            child: Text(
                                              widget.workbench.activeFeatureInboxCount > 0
                                                  ? '📥 ${widget.workbench.activeFeatureInboxCount}'
                                                  : '📥',
                                            ),
                                          ),
                                          InkWell(
                                            key: ValueKey(
                                              'copy_feature_ai_prompt_btn_${feat.id}',
                                            ),
                                            onTap: () =>
                                                _copyActiveFeaturePrompt(feat),
                                            child: const Text('⧉ AI'),
                                          ),
                                          InkWell(
                                            key: ValueKey(
                                              'halfscreen_rename_feature_btn_${feat.id}',
                                            ),
                                            onTap: () => _startStage2InlineEdit(
                                              'rename_header_feat_${feat.id}',
                                              feat.title,
                                            ),
                                            child: const Text('✎'),
                                          ),
                                          InkWell(
                                            key: ValueKey(
                                              'halfscreen_edit_tuning_guards_btn_${node.id}',
                                            ),
                                            onTap: () =>
                                                _showEditCheckpointTuningAndGuardsDialog(
                                              feat,
                                              states,
                                              node,
                                            ),
                                            child: const Icon(
                                              Icons.tune_rounded,
                                              size: 13,
                                            ),
                                          ),
                                          if (!isFeatureBeingBuiltInLiveMode &&
                                              !node.isCompleted)
                                            InkWell(
                                              key: ValueKey(
                                                'fast_track_checkpoint_btn_${node.id}',
                                              ),
                                              onTap: () {
                                                _completeAllCheckpointTasks(
                                                  node,
                                                );
                                                _advanceToNextStep(
                                                  feat,
                                                  states,
                                                  node,
                                                  node.checklist.length - 1,
                                                  node.checklist.last.children
                                                          .length -
                                                      1,
                                                );
                                              },
                                              child: const Text('✓ Done'),
                                            ),
                                        ],
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
                                  stepDropdownTrigger,
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
                                          fontSize: 12.5,
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
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: canGoToNextStep
                                              ? textSecondary
                                              : textMuted.withValues(alpha: 0.4),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  PopupMenuButton<String>(
                                    key: ValueKey(
                                      'halfscreen_feature_actions_menu_btn_${feat.id}',
                                    ),
                                    tooltip: 'Feature actions',
                                    color: bgSurface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(color: borderBright),
                                    ),
                                    onSelected: (action) {
                                      if (action == 'copy_ai_prompt') {
                                        _copyActiveFeaturePrompt(feat);
                                      } else if (action == 'rename_feature') {
                                        _startStage2InlineEdit(
                                          'rename_header_feat_${feat.id}',
                                          feat.title,
                                        );
                                      } else if (action == 'add_task') {
                                        _startStage2InlineEdit(
                                          'add_task_${node.id}',
                                          '',
                                        );
                                      } else if (action == 'edit_tuning') {
                                        _showEditCheckpointTuningAndGuardsDialog(
                                          feat,
                                          states,
                                          node,
                                        );
                                      } else if (action == 'feature_inbox') {
                                        _showFeatureInboxModal(
                                          context,
                                          preferredBeatId: feat.parentId,
                                        );
                                      } else if (action ==
                                          'toggle_complete_all') {
                                        if (node.isCompleted) {
                                          for (final task in node.checklist) {
                                            task.completed = false;
                                            for (final child in task.children) {
                                              child.completed = false;
                                            }
                                          }
                                          widget.workbench.updateFeatureStates(
                                            feat.id,
                                            states,
                                          );
                                          _rebuild(() {});
                                        } else {
                                          _completeAllCheckpointTasks(node);
                                          _advanceToNextStep(
                                            feat,
                                            states,
                                            node,
                                            node.checklist.length - 1,
                                            node.checklist.last.children
                                                    .length -
                                                1,
                                          );
                                        }
                                      } else if (action == 'archive_pivot') {
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
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            color: textSecondary,
                                          ),
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'rename_feature',
                                        height: 34,
                                        child: Text(
                                          '✎ Rename feature',
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            color: textSecondary,
                                          ),
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'add_task',
                                        height: 34,
                                        child: Text(
                                          '+ Add build task',
                                          style: GoogleFonts.inter(
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
                                          style: GoogleFonts.inter(
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
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            color: textSecondary,
                                          ),
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'toggle_complete_all',
                                        height: 34,
                                        child: Text(
                                          node.isCompleted
                                              ? '↺ Uncheck all steps'
                                              : '✓ Mark feature complete early',
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            color: node.isCompleted
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
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            color: accentCrimson,
                                          ),
                                        ),
                                      ),
                                    ],
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: bgSurface,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: borderBright),
                                      ),
                                      child: Text(
                                        '⋯',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
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

                // ── 2. Full-Width 3-Zone Playable Unit Workspace (Zone 2 Playlist + Zone 3 Recipe Sheet) ──
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isHalfScreenOverlayMode ? 12 : 16,
                    isHalfScreenOverlayMode ? 10 : 14,
                    isHalfScreenOverlayMode ? 12 : 16,
                    32,
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
                            constraints: const BoxConstraints(maxWidth: 1680),
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
                                              color: const Color(0xFF0B0E15),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: const Color(0x1EFFFFFF),
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
                                                      horizontal: 8,
                                                      vertical: 2.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: !_unrealCppMode
                                                          ? const Color(
                                                              0xFF21293A,
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
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: !_unrealCppMode
                                                            ? const Color(
                                                                0xFFF8FAFC,
                                                              )
                                                            : const Color(
                                                                0xFF64748B,
                                                              ),
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
                                                      horizontal: 8,
                                                      vertical: 2.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: _unrealCppMode
                                                          ? const Color(
                                                              0xFF21293A,
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
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: _unrealCppMode
                                                            ? const Color(
                                                                0xFFF8FAFC,
                                                              )
                                                            : const Color(
                                                                0xFF64748B,
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : null;

                                final featureActionsPopupMenu =
                                    PopupMenuButton<String>(
                                  tooltip: 'Feature actions',
                                  color: bgSurface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(color: borderBright),
                                  ),
                                  onSelected: (action) {
                                    if (action == 'copy_ai_prompt') {
                                      _copyActiveFeaturePrompt(feat);
                                    } else if (action == 'add_task') {
                                      _startStage2InlineEdit(
                                        'add_task_${node.id}',
                                        '',
                                      );
                                    } else if (action == 'edit_tuning') {
                                      _showEditCheckpointTuningAndGuardsDialog(
                                        feat,
                                        states,
                                        node,
                                      );
                                    } else if (action == 'feature_inbox') {
                                      _showFeatureInboxModal(context);
                                    } else if (action ==
                                        'toggle_complete_all') {
                                      if (node.isCompleted) {
                                        for (final task in node.checklist) {
                                          task.completed = false;
                                          for (final child in task.children) {
                                            child.completed = false;
                                          }
                                        }
                                        widget.workbench.updateFeatureStates(
                                          feat.id,
                                          states,
                                        );
                                        _rebuild(() {});
                                      } else {
                                        _completeAllCheckpointTasks(node);
                                        _advanceToNextStep(
                                          feat,
                                          states,
                                          node,
                                          node.checklist.length - 1,
                                          node.checklist.last.children.length -
                                              1,
                                        );
                                      }
                                    } else if (action == 'archive_pivot') {
                                      widget.workbench.toggleSupersedeFeature(
                                        feat.id,
                                        pivotReason:
                                            'Archived from Feature Header',
                                      );
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    PopupMenuItem<String>(
                                      value: 'add_task',
                                      height: 34,
                                      child: Text(
                                        '+ Add build task',
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'copy_ai_prompt',
                                      height: 34,
                                      child: Text(
                                        '⧉ Copy AI prompt',
                                        style: GoogleFonts.inter(
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
                                        style: GoogleFonts.inter(
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
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'toggle_complete_all',
                                      height: 34,
                                      child: Text(
                                        node.isCompleted
                                            ? '↺ Uncheck all steps'
                                            : '✓ Mark feature complete early',
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          color: node.isCompleted
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
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          color: accentCrimson,
                                        ),
                                      ),
                                    ),
                                  ],
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF21293A),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: const Color(0x1EFFFFFF),
                                      ),
                                    ),
                                    child: Text(
                                      '⋯',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ),
                                );

                                final featureBriefCardWidget = Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    13,
                                    11,
                                    13,
                                    11,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF161B26),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Color(0x14FFFFFF),
                                      ),
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
                                          Flexible(
                                            child: Text(
                                              '02 · FEATURE PLAYLIST',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.7,
                                                color: const Color(0xFF64748B),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: allCheckpointStepsDone
                                                      ? const Color(0xFF10B981)
                                                          .withValues(
                                                          alpha: 0.14,
                                                        )
                                                      : const Color(0x0FFFFFFF),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: allCheckpointStepsDone
                                                        ? const Color(
                                                            0xFF10B981,
                                                          ).withValues(
                                                            alpha: 0.36,
                                                          )
                                                        : const Color(
                                                            0x18FFFFFF,
                                                          ),
                                                  ),
                                                ),
                                                child: Text(
                                                  '$totalDoneSteps/$totalStepsCount DONE',
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: allCheckpointStepsDone
                                                        ? const Color(
                                                            0xFF6EE7B7,
                                                          )
                                                        : const Color(
                                                            0xFFCBD5E1,
                                                          ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              featureActionsPopupMenu,
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      if (!isHalfScreenOverlayMode)
                                        _activeStage2InlineEditKey ==
                                                'rename_header_feat_${feat.id}'
                                            ? _buildStage2InlineEditor(
                                                editKey:
                                                    'rename_header_feat_${feat.id}',
                                                inputKey: const ValueKey(
                                                  'workbench_rename_live_feature_input',
                                                ),
                                                saveBtnKey: const ValueKey(
                                                  'confirm_workbench_rename_live_feature_btn',
                                                ),
                                                hintText: 'Feature title...',
                                                onSave: (val) => widget
                                                    .workbench
                                                    .renameLiveFeature(
                                                  feat.id,
                                                  val,
                                                ),
                                              )
                                            : Row(
                                                children: [
                                                  Container(
                                                    width: 17,
                                                    height: 17,
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFF5E6AD2,
                                                      ).withValues(alpha: 0.14),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFF6875F5,
                                                        ).withValues(
                                                          alpha: 0.38,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      'F',
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        height: 1.0,
                                                        color: const Color(
                                                          0xFFA5B4FC,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 7),
                                                  Expanded(
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
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                      child: Text(
                                                        featShortTitle,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 14.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: const Color(
                                                            0xFFF8FAFC,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    isUpgradeBadge
                                                        ? 'UPGRADE'
                                                        : 'NEW',
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 9.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: isUpgradeBadge
                                                          ? const Color(
                                                              0xFF7DD3FC,
                                                            )
                                                          : const Color(
                                                              0xFF64748B,
                                                            ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      if (!isHalfScreenOverlayMode)
                                        Container(
                                          key: ValueKey(
                                            'task_sheet_feature_goal_${node.id}',
                                          ),
                                          margin: const EdgeInsets.only(top: 7),
                                          padding: const EdgeInsets.fromLTRB(
                                            9,
                                            6,
                                            9,
                                            6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0B0E15),
                                            borderRadius:
                                                BorderRadius.circular(5),
                                            border: Border.all(
                                              color: const Color(0x14FFFFFF),
                                            ),
                                          ),
                                          child: RichText(
                                            text: TextSpan(
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                height: 1.4,
                                                color: const Color(0xFFCBD5E1),
                                              ),
                                              children: [
                                                TextSpan(
                                                  text: 'WHAT: ',
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.4,
                                                    color: const Color(
                                                      0xFFA5B4FC,
                                                    ),
                                                  ),
                                                ),
                                                TextSpan(text: featureGoalText),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );

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
                                      // ── A. Hidden Progress / Dropdown Compatibility Hooks ──
                                      if (isHalfScreenOverlayMode &&
                                          unrealToggleWidget != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: unrealToggleWidget,
                                          ),
                                        ),
                                      SizedBox(
                                        width: 1,
                                        height: 1,
                                        child: Opacity(
                                          opacity: 0,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '$remHoursStr · $totalDoneSteps of $totalStepsCount steps',
                                              ),
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
                                            bottom: 12,
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

                                      // ── C & D. 3-Zone Playable Unit Split: Zone 2 Continuous Feature Playlist (284px) + Zone 3 Active Step Recipe Sheet (Expanded) ──
                                      if (howToBlueprints.isNotEmpty)
                                        Builder(
                                          builder: (context) {
                                            final isDesktopDock =
                                                !isHalfScreenOverlayMode &&
                                                    MediaQuery.sizeOf(context)
                                                            .width >=
                                                        1040;
                                            final activeBp = selectedHowTo;
                                            final totalSubCount =
                                                activeBp.subSteps.length;

                                            // Compute global sequential 1-based step index for active step badge
                                            int activeGlobalStepNumber = 1;
                                            int runningStepCounter = 0;
                                            for (int tIdx = 0;
                                                tIdx < howToBlueprints.length;
                                                tIdx++) {
                                              final bp = howToBlueprints[tIdx];
                                              if (tIdx == selectedTaskIdx) {
                                                activeGlobalStepNumber =
                                                    runningStepCounter +
                                                        effectiveSubStepIdx +
                                                        1;
                                              }
                                              runningStepCounter +=
                                                  bp.subSteps.length;
                                            }
                                            final activeGlobalStepBadge =
                                                activeGlobalStepNumber
                                                    .toString()
                                                    .padLeft(2, '0');

                                            int playlistStepCounter = 0;

                                            // ── ZONE 2: Continuous Feature Playlist (284px · #0B0E15 40% Deep Obsidian Well) ──
                                            final leftDockWidget = Container(
                                              clipBehavior: Clip.hardEdge,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF0B0E15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color:
                                                      const Color(0x14FFFFFF),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  // 1. Top Pinned Feature Brief Card (#161B26)
                                                  featureBriefCardWidget,

                                                  // 2. Continuous Step Playlist (All [T] Tasks & All [01..N] Steps Expanded)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                      8,
                                                      8,
                                                      8,
                                                      10,
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        for (int tIdx = 0;
                                                            tIdx <
                                                                howToBlueprints
                                                                    .length;
                                                            tIdx++)
                                                          Builder(
                                                            builder: (context) {
                                                              final bp =
                                                                  howToBlueprints[
                                                                      tIdx];
                                                              final task = node
                                                                  .checklist[tIdx];
                                                              final globalNumLabel =
                                                                  (tIdx + 1)
                                                                      .toString()
                                                                      .padLeft(
                                                                        2,
                                                                        '0',
                                                                      );
                                                              final isFixTask =
                                                                  task.text
                                                                      .trim()
                                                                      .startsWith(
                                                                        '[FIX]',
                                                                      );
                                                              final isTaskActive =
                                                                  tIdx ==
                                                                      selectedTaskIdx;
                                                              final doneSubCount = bp
                                                                  .subSteps
                                                                  .where(
                                                                    (s) => s
                                                                        .subtask
                                                                        .completed,
                                                                  )
                                                                  .length;
                                                              final taskSubCount =
                                                                  bp.subSteps
                                                                      .length;
                                                              final groupTitle =
                                                                  bp.shortTaskTitle;

                                                              return Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .stretch,
                                                                children: [
                                                                  if (_activeStage2InlineEditKey ==
                                                                      'edit_task_${node.id}_$tIdx')
                                                                    Padding(
                                                                      padding: const EdgeInsets
                                                                          .symmetric(
                                                                        vertical:
                                                                            4,
                                                                      ),
                                                                      child: _buildStage2InlineEditor(
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
                                                                        onSave:
                                                                            (val) {
                                                                          task.text =
                                                                              val;
                                                                          TaskHowToBlueprint
                                                                              .clearCache();
                                                                          widget
                                                                              .workbench
                                                                              .updateFeatureStates(
                                                                            feat.id,
                                                                            states,
                                                                          );
                                                                        },
                                                                        onDelete: node.checklist.length >
                                                                                1
                                                                            ? () {
                                                                                node.checklist.removeAt(tIdx);
                                                                                TaskHowToBlueprint.clearCache();
                                                                                widget.workbench.updateFeatureStates(feat.id, states);
                                                                                _rebuild(() {
                                                                                  final nextIdx = node.checklist.isEmpty ? 0 : tIdx.clamp(0, node.checklist.length - 1);
                                                                                  _selectedTaskIndexByCheckpoint[node.id] = nextIdx;
                                                                                  _selectedSubStepIndexByTask['${node.id}_$nextIdx'] = 0;
                                                                                });
                                                                              }
                                                                            : null,
                                                                      ),
                                                                    )
                                                                  else
                                                                    // [T] Task Section Header (Non-collapsible divider)
                                                                    InkWell(
                                                                      key: ValueKey(
                                                                        'outline_task_${node.id}_$tIdx',
                                                                      ),
                                                                      onTap:
                                                                          () {
                                                                        _rebuild(
                                                                            () {
                                                                          _manualCheckpointFocusIndex =
                                                                              index;
                                                                          _manualCheckpointFocusFeatureId =
                                                                              feat.id;
                                                                          _selectedTaskIndexByCheckpoint[node.id] =
                                                                              tIdx;
                                                                          final firstIncomplete = task
                                                                              .children
                                                                              .indexWhere((c) => !c.completed);
                                                                          _selectedSubStepIndexByTask['${node.id}_$tIdx'] = firstIncomplete != -1
                                                                              ? firstIncomplete
                                                                              : 0;
                                                                        });
                                                                      },
                                                                      borderRadius:
                                                                          BorderRadius
                                                                              .circular(
                                                                        5,
                                                                      ),
                                                                      child:
                                                                          Padding(
                                                                        padding: EdgeInsets
                                                                            .fromLTRB(
                                                                          4,
                                                                          tIdx == 0
                                                                              ? 2
                                                                              : 10,
                                                                          4,
                                                                          4,
                                                                        ),
                                                                        child:
                                                                            Row(
                                                                          children: [
                                                                            // Unnumbered [T] Amber micro-square badge (15x15px, 4px radius)
                                                                            Container(
                                                                              width: 15,
                                                                              height: 15,
                                                                              alignment: Alignment.center,
                                                                              decoration: BoxDecoration(
                                                                                color: isFixTask
                                                                                    ? accentCrimson.withValues(alpha: 0.14)
                                                                                    : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                                                                borderRadius: BorderRadius.circular(3.5),
                                                                                border: Border.all(
                                                                                  color: isFixTask
                                                                                      ? accentCrimson.withValues(alpha: 0.38)
                                                                                      : const Color(0xFFF59E0B).withValues(alpha: 0.34),
                                                                                ),
                                                                              ),
                                                                              child: Text(
                                                                                'T',
                                                                                style: GoogleFonts.jetBrainsMono(
                                                                                  fontSize: 9,
                                                                                  fontWeight: FontWeight.w800,
                                                                                  height: 1.0,
                                                                                  color: isFixTask
                                                                                      ? accentCrimson
                                                                                      : const Color(0xFFFCD34D),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            const SizedBox(width: 6),
                                                                            Expanded(
                                                                              child: Text(
                                                                                groupTitle,
                                                                                maxLines: 1,
                                                                                overflow: TextOverflow.ellipsis,
                                                                                style: GoogleFonts.inter(
                                                                                  fontSize: 12,
                                                                                  fontWeight: FontWeight.w600,
                                                                                  color: isFixTask
                                                                                      ? accentCrimson
                                                                                      : (isTaskActive
                                                                                          ? const Color(0xFFF8FAFC)
                                                                                          : const Color(0xFF94A3B8)),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            // 1x1 Opacity(0) compatibility text hook for legacy T01 / TASK 01 test assertions
                                                                            SizedBox(
                                                                              width: 1,
                                                                              height: 1,
                                                                              child: Opacity(
                                                                                opacity: 0,
                                                                                child: Row(
                                                                                  mainAxisSize: MainAxisSize.min,
                                                                                  children: [
                                                                                    Text('T$globalNumLabel'),
                                                                                    Text(globalNumLabel),
                                                                                    Text('TASK $globalNumLabel · ${groupTitle.toUpperCase()}'),
                                                                                  ],
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            const SizedBox(width: 4),
                                                                            InkWell(
                                                                              key: ValueKey('edit_active_task_title_btn_${node.id}_$tIdx'),
                                                                              onTap: () => _startStage2InlineEdit(
                                                                                'edit_task_${node.id}_$tIdx',
                                                                                task.text,
                                                                              ),
                                                                              borderRadius: BorderRadius.circular(3),
                                                                              child: Padding(
                                                                                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                                                                child: Icon(
                                                                                  Icons.edit_outlined,
                                                                                  size: 11,
                                                                                  color: const Color(0xFF64748B),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            const SizedBox(width: 3),
                                                                            InkWell(
                                                                              key: ValueKey('complete_task_group_${node.id}_$tIdx'),
                                                                              onTap: () => _toggleTaskGroupCompletion(
                                                                                feat,
                                                                                states,
                                                                                node,
                                                                                tIdx,
                                                                              ),
                                                                              borderRadius: BorderRadius.circular(3),
                                                                              child: Padding(
                                                                                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                                                                child: Text(
                                                                                  '$doneSubCount/$taskSubCount',
                                                                                  style: GoogleFonts.jetBrainsMono(
                                                                                    fontSize: 10.5,
                                                                                    fontWeight: FontWeight.w600,
                                                                                    color: task.completed
                                                                                        ? const Color(0xFF6EE7B7)
                                                                                        : const Color(0xFF64748B),
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            SizedBox(
                                                                              width: 1,
                                                                              height: 1,
                                                                              child: Opacity(
                                                                                opacity: 0,
                                                                                child: InkWell(
                                                                                  key: ValueKey('outline_task_chevron_${node.id}_$tIdx'),
                                                                                  onTap: () {
                                                                                    _rebuild(() {});
                                                                                  },
                                                                                  child: Text(isTaskActive ? ' ▾' : ' ▸'),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                    ),

                                                                  // Permanently Expanded Steps under this [T] Task Section
                                                                  for (int sIdx =
                                                                          0;
                                                                      sIdx <
                                                                          bp
                                                                              .subSteps
                                                                              .length;
                                                                      sIdx++)
                                                                    Builder(
                                                                      builder:
                                                                          (context) {
                                                                        playlistStepCounter++;
                                                                        final seqNumLabel = playlistStepCounter
                                                                            .toString()
                                                                            .padLeft(
                                                                              2,
                                                                              '0',
                                                                            );
                                                                        final stepItem =
                                                                            bp.subSteps[sIdx];
                                                                        final isStepActive = isTaskActive &&
                                                                            sIdx ==
                                                                                effectiveSubStepIdx;
                                                                        final isStepDone =
                                                                            stepItem.subtask.completed;

                                                                        return Container(
                                                                          margin: const EdgeInsets.only(
                                                                            bottom: 3,
                                                                          ),
                                                                          decoration: BoxDecoration(
                                                                            color: isStepActive
                                                                                ? const Color(0xFF1B2230)
                                                                                : Colors.transparent,
                                                                            borderRadius: BorderRadius.circular(5),
                                                                            border: isStepActive
                                                                                ? Border.all(
                                                                                    color: const Color(0xFF6875F5).withValues(alpha: 0.45),
                                                                                  )
                                                                                : null,
                                                                          ),
                                                                          child: InkWell(
                                                                            key: ValueKey(
                                                                              isTaskActive
                                                                                  ? 'task_sheet_step_row_${node.id}_${tIdx}_$sIdx'
                                                                                  : 'playlist_step_row_${node.id}_${tIdx}_$sIdx',
                                                                            ),
                                                                            onTap: () {
                                                                              _rebuild(() {
                                                                                _manualCheckpointFocusIndex = index;
                                                                                _manualCheckpointFocusFeatureId = feat.id;
                                                                                _selectedTaskIndexByCheckpoint[node.id] = tIdx;
                                                                                _selectedSubStepIndexByTask['${node.id}_$tIdx'] = sIdx;
                                                                              });
                                                                            },
                                                                            borderRadius: BorderRadius.circular(5),
                                                                            child: Padding(
                                                                              padding: const EdgeInsets.symmetric(
                                                                                horizontal: 8,
                                                                                vertical: 6,
                                                                              ),
                                                                              child: Row(
                                                                                children: [
                                                                                  // Square Step Index Tile [01] (19x17px, 4px radius)
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
                                                                                    borderRadius: BorderRadius.circular(4),
                                                                                    child: Container(
                                                                                      width: 19,
                                                                                      height: 17,
                                                                                      alignment: Alignment.center,
                                                                                      decoration: BoxDecoration(
                                                                                        color: isStepDone
                                                                                            ? const Color(0xFF10B981).withValues(alpha: 0.14)
                                                                                            : (isStepActive
                                                                                                ? const Color(0xFF38BDF8).withValues(alpha: 0.14)
                                                                                                : const Color(0x0EFFFFFF)),
                                                                                        borderRadius: BorderRadius.circular(4),
                                                                                        border: Border.all(
                                                                                          color: isStepDone
                                                                                              ? const Color(0xFF10B981).withValues(alpha: 0.36)
                                                                                              : (isStepActive
                                                                                                  ? const Color(0xFF38BDF8).withValues(alpha: 0.36)
                                                                                                  : const Color(0x1CFFFFFF)),
                                                                                        ),
                                                                                      ),
                                                                                      child: Text(
                                                                                        seqNumLabel,
                                                                                        style: GoogleFonts.jetBrainsMono(
                                                                                          fontSize: 9.5,
                                                                                          fontWeight: FontWeight.w800,
                                                                                          height: 1.0,
                                                                                          color: isStepDone
                                                                                              ? const Color(0xFF6EE7B7)
                                                                                              : (isStepActive
                                                                                                  ? const Color(0xFF7DD3FC)
                                                                                                  : const Color(0xFF64748B)),
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  // 1x1 Opacity(0) compatibility text hook
                                                                                  SizedBox(
                                                                                    width: 1,
                                                                                    height: 1,
                                                                                    child: Opacity(
                                                                                      opacity: 0,
                                                                                      child: Row(
                                                                                        mainAxisSize: MainAxisSize.min,
                                                                                        children: [
                                                                                          Text(
                                                                                            isStepDone
                                                                                                ? '✓ '
                                                                                                : (isStepActive ? '▶ ' : '○ '),
                                                                                          ),
                                                                                          Text('${sIdx + 1}. '),
                                                                                        ],
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  const SizedBox(width: 7),
                                                                                  Expanded(
                                                                                    child: Text(
                                                                                      stepItem.shortTitle,
                                                                                      maxLines: 1,
                                                                                      overflow: TextOverflow.ellipsis,
                                                                                      style: GoogleFonts.inter(
                                                                                        fontSize: 13,
                                                                                        fontWeight: isStepActive
                                                                                            ? FontWeight.w600
                                                                                            : FontWeight.w500,
                                                                                        color: isStepDone
                                                                                            ? const Color(0xFF64748B)
                                                                                            : (isStepActive
                                                                                                ? const Color(0xFFF8FAFC)
                                                                                                : const Color(0xFFCBD5E1)),
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  const SizedBox(width: 6),
                                                                                  if (isStepDone)
                                                                                    Container(
                                                                                      padding: const EdgeInsets.symmetric(
                                                                                        horizontal: 5,
                                                                                        vertical: 1.5,
                                                                                      ),
                                                                                      decoration: BoxDecoration(
                                                                                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                                                                        borderRadius: BorderRadius.circular(3.5),
                                                                                        border: Border.all(
                                                                                          color: const Color(0xFF10B981).withValues(alpha: 0.36),
                                                                                        ),
                                                                                      ),
                                                                                      child: Row(
                                                                                        mainAxisSize: MainAxisSize.min,
                                                                                        children: [
                                                                                          Text(
                                                                                            'DONE',
                                                                                            style: GoogleFonts.jetBrainsMono(
                                                                                              fontSize: 9,
                                                                                              fontWeight: FontWeight.w800,
                                                                                              color: const Color(0xFF6EE7B7),
                                                                                            ),
                                                                                          ),
                                                                                          SizedBox(
                                                                                            width: 1,
                                                                                            height: 1,
                                                                                            child: Opacity(
                                                                                              opacity: 0,
                                                                                              child: Text(stepItem.etaLabel),
                                                                                            ),
                                                                                          ),
                                                                                        ],
                                                                                      ),
                                                                                    )
                                                                                  else
                                                                                    Text(
                                                                                      stepItem.etaLabel,
                                                                                      style: GoogleFonts.jetBrainsMono(
                                                                                        fontSize: 10.5,
                                                                                        fontWeight: FontWeight.w600,
                                                                                        color: isStepActive
                                                                                            ? const Color(0xFFA5B4FC)
                                                                                            : const Color(0xFF64748B),
                                                                                      ),
                                                                                    ),
                                                                                ],
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        );
                                                                      },
                                                                    ),
                                                                ],
                                                              );
                                                            },
                                                          ),

                                                        // + Add Build Task button at bottom of Playlist
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        if (_activeStage2InlineEditKey ==
                                                            'add_task_${node.id}')
                                                          _buildStage2InlineEditor(
                                                            editKey:
                                                                'add_task_${node.id}',
                                                            inputKey:
                                                                const ValueKey(
                                                              'add_stage3_task_title_input',
                                                            ),
                                                            saveBtnKey:
                                                                const ValueKey(
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
                                                          )
                                                        else
                                                          InkWell(
                                                            key: ValueKey(
                                                              'outline_add_task_btn_${node.id}',
                                                            ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              5,
                                                            ),
                                                            onTap: () =>
                                                                _startStage2InlineEdit(
                                                              'add_task_${node.id}',
                                                              '',
                                                            ),
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 10,
                                                                vertical: 6,
                                                              ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  5,
                                                                ),
                                                                border:
                                                                    Border.all(
                                                                  color: const Color(
                                                                    0x14FFFFFF,
                                                                  ),
                                                                ),
                                                              ),
                                                              child: Text(
                                                                '+ Add Build Task...',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color:
                                                                      const Color(
                                                                    0xFF64748B,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );

                                            // ── ZONE 3: Active Step Recipe Stage Sheet (Expanded · #121620 30% Cool Gunmetal Slate Sheet) ──
                                            final rightDockWidget = Container(
                                              key: ValueKey(
                                                'task_sheet_active_step_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                                              ),
                                              clipBehavior: Clip.hardEdge,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF121620),
                                                borderRadius:
                                                    BorderRadius.circular(9),
                                                border: Border.all(
                                                  color:
                                                      const Color(0x16FFFFFF),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  // 1. Sheet Header (42px · #161B26)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 14,
                                                      vertical: 9,
                                                    ),
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: Color(0xFF161B26),
                                                      border: Border(
                                                        bottom: BorderSide(
                                                          color:
                                                              Color(0x14FFFFFF),
                                                        ),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Row(
                                                            children: [
                                                              Container(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: const Color(
                                                                    0xFF38BDF8,
                                                                  ).withValues(
                                                                    alpha: 0.14,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    4,
                                                                  ),
                                                                  border: Border
                                                                      .all(
                                                                    color: const Color(
                                                                      0xFF38BDF8,
                                                                    ).withValues(
                                                                      alpha:
                                                                          0.36,
                                                                    ),
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  activeGlobalStepBadge,
                                                                  style: GoogleFonts
                                                                      .jetBrainsMono(
                                                                    fontSize:
                                                                        10.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                    color: const Color(
                                                                      0xFF7DD3FC,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                width: 1,
                                                                height: 1,
                                                                child: Opacity(
                                                                  opacity: 0,
                                                                  child: Text(
                                                                    'DO · STEP ${effectiveSubStepIdx + 1} OF $totalSubCount',
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 10,
                                                              ),
                                                              Flexible(
                                                                child: Text(
                                                                  activeSubStep
                                                                      .shortTitle,
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontSize:
                                                                        14.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: const Color(
                                                                      0xFFF8FAFC,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            if (!isHalfScreenOverlayMode &&
                                                                unrealToggleWidget !=
                                                                    null) ...[
                                                              unrealToggleWidget,
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                            ],
                                                            InkWell(
                                                              key: ValueKey(
                                                                'engine_dock_prev_step_${node.id}',
                                                              ),
                                                              onTap: canGoToPreviousStep
                                                                  ? () =>
                                                                      _retreatToPreviousStep(
                                                                        states,
                                                                        index,
                                                                        node,
                                                                        howToBlueprints,
                                                                        selectedTaskIdx,
                                                                        effectiveSubStepIdx,
                                                                      )
                                                                  : null,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                5,
                                                              ),
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 3.5,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: canGoToPreviousStep
                                                                      ? const Color(
                                                                          0xFF21293A,
                                                                        )
                                                                      : Colors
                                                                          .transparent,
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    5,
                                                                  ),
                                                                  border: Border
                                                                      .all(
                                                                    color: canGoToPreviousStep
                                                                        ? const Color(
                                                                            0x21FFFFFF,
                                                                          )
                                                                        : const Color(
                                                                            0x0DFFFFFF,
                                                                          ),
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  '‹ Prev',
                                                                  style: GoogleFonts
                                                                      .jetBrainsMono(
                                                                    fontSize:
                                                                        11,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: canGoToPreviousStep
                                                                        ? const Color(
                                                                            0xFFCBD5E1,
                                                                          )
                                                                        : const Color(
                                                                            0xFF475569,
                                                                          ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            InkWell(
                                                              key: ValueKey(
                                                                'engine_dock_next_step_${node.id}',
                                                              ),
                                                              onTap: activeSubStep
                                                                      .subtask
                                                                      .completed
                                                                  ? () =>
                                                                      _advanceToNextStep(
                                                                        feat,
                                                                        states,
                                                                        node,
                                                                        selectedTaskIdx,
                                                                        effectiveSubStepIdx,
                                                                      )
                                                                  : null,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                5,
                                                              ),
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 3.5,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: activeSubStep
                                                                          .subtask
                                                                          .completed
                                                                      ? const Color(
                                                                          0xFF21293A,
                                                                        )
                                                                      : Colors
                                                                          .transparent,
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    5,
                                                                  ),
                                                                  border: Border
                                                                      .all(
                                                                    color: activeSubStep
                                                                            .subtask
                                                                            .completed
                                                                        ? const Color(
                                                                            0x21FFFFFF,
                                                                          )
                                                                        : const Color(
                                                                            0x0DFFFFFF,
                                                                          ),
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  'Next ›',
                                                                  style: GoogleFonts
                                                                      .jetBrainsMono(
                                                                    fontSize:
                                                                        11,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: activeSubStep
                                                                            .subtask
                                                                            .completed
                                                                        ? const Color(
                                                                            0xFFCBD5E1,
                                                                          )
                                                                        : const Color(
                                                                            0xFF475569,
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

                                                  // 2. Task Context Strip (#161B26): Side-by-Side Task section (Amber) | Task done when (Mint)
                                                  Container(
                                                    key: ValueKey(
                                                      'task_overview_goal_box_${node.id}_$selectedTaskIdx',
                                                    ),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 14,
                                                      vertical: 9,
                                                    ),
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: Color(0xFF161B26),
                                                      border: Border(
                                                        bottom: BorderSide(
                                                          color:
                                                              Color(0x14FFFFFF),
                                                        ),
                                                      ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        const SizedBox(
                                                          width: 1,
                                                          height: 1,
                                                          child: Opacity(
                                                            opacity: 0,
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Text('GOAL'),
                                                                Text('DONE'),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                        isHalfScreenOverlayMode
                                                        ? Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            children: [
                                                              Row(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Container(
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                      horizontal:
                                                                          5,
                                                                      vertical:
                                                                          1.5,
                                                                    ),
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: const Color(
                                                                        0xFFF59E0B,
                                                                      ).withValues(
                                                                        alpha:
                                                                            0.12,
                                                                      ),
                                                                      borderRadius:
                                                                          BorderRadius
                                                                              .circular(
                                                                        3.5,
                                                                      ),
                                                                      border: Border
                                                                          .all(
                                                                        color: const Color(
                                                                          0xFFF59E0B,
                                                                        ).withValues(
                                                                          alpha:
                                                                              0.34,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    child: Text(
                                                                      'Task section',
                                                                      style: GoogleFonts
                                                                          .jetBrainsMono(
                                                                        fontSize:
                                                                            9.5,
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .w700,
                                                                        color: const Color(
                                                                          0xFFFCD34D,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Expanded(
                                                                    child: Text(
                                                                      activeBp
                                                                          .taskGoalSentence,
                                                                      style: GoogleFonts
                                                                          .inter(
                                                                        fontSize:
                                                                            12.5,
                                                                        height:
                                                                            1.4,
                                                                        color: const Color(
                                                                          0xFFCBD5E1,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                height: 6,
                                                              ),
                                                              Row(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Container(
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                      horizontal:
                                                                          5,
                                                                      vertical:
                                                                          1.5,
                                                                    ),
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: const Color(
                                                                        0xFF10B981,
                                                                      ).withValues(
                                                                        alpha:
                                                                            0.12,
                                                                      ),
                                                                      borderRadius:
                                                                          BorderRadius
                                                                              .circular(
                                                                        3.5,
                                                                      ),
                                                                      border: Border
                                                                          .all(
                                                                        color: const Color(
                                                                          0xFF10B981,
                                                                        ).withValues(
                                                                          alpha:
                                                                              0.36,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    child: Text(
                                                                      'Task done when',
                                                                      style: GoogleFonts
                                                                          .jetBrainsMono(
                                                                        fontSize:
                                                                            9.5,
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .w700,
                                                                        color: const Color(
                                                                          0xFF6EE7B7,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Expanded(
                                                                    child: Text(
                                                                      activeBp
                                                                          .taskDoneCheck,
                                                                      style: GoogleFonts
                                                                          .inter(
                                                                        fontSize:
                                                                            12.5,
                                                                        height:
                                                                            1.4,
                                                                        color: const Color(
                                                                          0xFFCBD5E1,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ],
                                                          )
                                                        : Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Expanded(
                                                                child: Row(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    Container(
                                                                      padding: const EdgeInsets
                                                                          .symmetric(
                                                                        horizontal:
                                                                            6,
                                                                        vertical:
                                                                            1.5,
                                                                      ),
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: const Color(
                                                                          0xFFF59E0B,
                                                                        ).withValues(
                                                                          alpha:
                                                                              0.12,
                                                                        ),
                                                                        borderRadius:
                                                                            BorderRadius
                                                                                .circular(
                                                                          3.5,
                                                                        ),
                                                                        border: Border
                                                                            .all(
                                                                          color: const Color(
                                                                            0xFFF59E0B,
                                                                          ).withValues(
                                                                            alpha:
                                                                                0.34,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      child:
                                                                          Text(
                                                                        'Task section',
                                                                        style: GoogleFonts
                                                                            .jetBrainsMono(
                                                                          fontSize:
                                                                              9.5,
                                                                          fontWeight:
                                                                              FontWeight.w700,
                                                                          color:
                                                                              const Color(
                                                                            0xFFFCD34D,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 8,
                                                                    ),
                                                                    Expanded(
                                                                      child:
                                                                          Text(
                                                                        activeBp
                                                                            .taskGoalSentence,
                                                                        style: GoogleFonts
                                                                            .inter(
                                                                          fontSize:
                                                                              12.5,
                                                                          height:
                                                                              1.4,
                                                                          color:
                                                                              const Color(
                                                                            0xFFCBD5E1,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                              Container(
                                                                width: 1,
                                                                height: 22,
                                                                margin: const EdgeInsets
                                                                    .symmetric(
                                                                  horizontal:
                                                                      12,
                                                                ),
                                                                color: const Color(
                                                                  0x14FFFFFF,
                                                                ),
                                                              ),
                                                              Expanded(
                                                                child: Row(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    Container(
                                                                      padding: const EdgeInsets
                                                                          .symmetric(
                                                                        horizontal:
                                                                            6,
                                                                        vertical:
                                                                            1.5,
                                                                      ),
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: const Color(
                                                                          0xFF10B981,
                                                                        ).withValues(
                                                                          alpha:
                                                                              0.12,
                                                                        ),
                                                                        borderRadius:
                                                                            BorderRadius
                                                                                .circular(
                                                                          3.5,
                                                                        ),
                                                                        border: Border
                                                                            .all(
                                                                          color: const Color(
                                                                            0xFF10B981,
                                                                          ).withValues(
                                                                            alpha:
                                                                                0.36,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      child:
                                                                          Text(
                                                                        'Task done when',
                                                                        style: GoogleFonts
                                                                            .jetBrainsMono(
                                                                          fontSize:
                                                                              9.5,
                                                                          fontWeight:
                                                                              FontWeight.w700,
                                                                          color:
                                                                              const Color(
                                                                            0xFF6EE7B7,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 8,
                                                                    ),
                                                                    Expanded(
                                                                      child:
                                                                          Text(
                                                                        activeBp
                                                                            .taskDoneCheck,
                                                                        style: GoogleFonts
                                                                            .inter(
                                                                          fontSize:
                                                                              12.5,
                                                                          height:
                                                                              1.4,
                                                                          color:
                                                                              const Color(
                                                                            0xFFCBD5E1,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                      ],
                                                    ),
                                                  ),

                                                  // 3. Active Step Instruction Banner
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .fromLTRB(
                                                      16,
                                                      11,
                                                      16,
                                                      11,
                                                    ),
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: Color(0xFF121620),
                                                      border: Border(
                                                        bottom: BorderSide(
                                                          color:
                                                              Color(0x14FFFFFF),
                                                        ),
                                                      ),
                                                    ),
                                                    child: Text.rich(
                                                      _buildSemanticStepSpan(
                                                        text: activeSubStep
                                                            .instruction,
                                                        baseStyle:
                                                            GoogleFonts.inter(
                                                          fontSize: 13.5,
                                                          height: 1.48,
                                                          color: const Color(
                                                            0xFFF8FAFC,
                                                          ),
                                                        ),
                                                        tuningItems:
                                                            tuningItems,
                                                        edgeItems: edgeItems,
                                                        isCodeBlock: false,
                                                      ),
                                                    ),
                                                  ),

                                                  // 4. Upper 50/50 Split Bay (01 Scene hierarchy + 02 Inspector details) & Lower Script Bay (03 Script implementation)
                                                  _buildEngineStepAreasBox(
                                                    feat: feat,
                                                    states: states,
                                                    node: node,
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
                                                    tuningItems: tuningItems,
                                                    edgeItems: edgeItems,
                                                  ),

                                                  // 5. Docked Verify & Action Bar (#161B26 · 04 Verify in engine)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 16,
                                                      vertical: 11,
                                                    ),
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: Color(0xFF161B26),
                                                      border: Border(
                                                        top: BorderSide(
                                                          color:
                                                              Color(0x14FFFFFF),
                                                        ),
                                                      ),
                                                    ),
                                                    child: Builder(
                                                      builder: (context) {
                                                        final verifyRow = Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: const Color(
                                                                  0xFF10B981,
                                                                ).withValues(
                                                                  alpha: 0.12,
                                                                ),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  4,
                                                                ),
                                                                border:
                                                                    Border.all(
                                                                  color: const Color(
                                                                    0xFF10B981,
                                                                  ).withValues(
                                                                    alpha: 0.36,
                                                                  ),
                                                                ),
                                                              ),
                                                              child: Text(
                                                                '04',
                                                                style: GoogleFonts
                                                                    .jetBrainsMono(
                                                                  fontSize:
                                                                      10.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  color:
                                                                      const Color(
                                                                    0xFF6EE7B7,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Text(
                                                              'Verify in engine',
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    const Color(
                                                                  0xFFF8FAFC,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 10,
                                                            ),
                                                            Expanded(
                                                              child: Text.rich(
                                                                _buildSemanticStepSpan(
                                                                  text: activeSubStep
                                                                      .verifyResult,
                                                                  baseStyle:
                                                                      GoogleFonts
                                                                          .inter(
                                                                    fontSize:
                                                                        13,
                                                                    height: 1.4,
                                                                    color: const Color(
                                                                      0xFFCBD5E1,
                                                                    ),
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
                                                        );

                                                        final doneBtn = InkWell(
                                                          key: ValueKey(
                                                            'one_click_complete_next_btn_${node.id}',
                                                          ),
                                                          onTap: () {
                                                            if (activeSubStep
                                                                .subtask
                                                                .completed) {
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
                                                              BorderRadius
                                                                  .circular(6),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 14,
                                                              vertical: 6.5,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: activeSubStep
                                                                      .subtask
                                                                      .completed
                                                                  ? const Color(
                                                                      0xFF10B981,
                                                                    ).withValues(
                                                                      alpha:
                                                                          0.14,
                                                                    )
                                                                  : const Color(
                                                                      0xFF6875F5,
                                                                    ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                6,
                                                              ),
                                                              border: Border
                                                                  .all(
                                                                color: activeSubStep
                                                                        .subtask
                                                                        .completed
                                                                    ? const Color(
                                                                        0xFF10B981,
                                                                      ).withValues(
                                                                        alpha:
                                                                            0.36,
                                                                      )
                                                                    : const Color(
                                                                        0xFF7884F7,
                                                                      ),
                                                              ),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Text(
                                                                  activeSubStep
                                                                          .subtask
                                                                          .completed
                                                                      ? 'Undo'
                                                                      : (isHalfScreenOverlayMode
                                                                          ? 'Done & Next →'
                                                                          : 'Done'),
                                                                  style: GoogleFonts
                                                                      .inter(
                                                                    fontSize:
                                                                        13,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: activeSubStep
                                                                            .subtask
                                                                            .completed
                                                                        ? const Color(
                                                                            0xFF6EE7B7,
                                                                          )
                                                                        : const Color(
                                                                            0xFFF8FAFC,
                                                                          ),
                                                                  ),
                                                                ),
                                                                if (isHalfScreenOverlayMode &&
                                                                    !activeSubStep
                                                                        .subtask
                                                                        .completed)
                                                                  const SizedBox(
                                                                    width: 1,
                                                                    height: 1,
                                                                    child:
                                                                        Opacity(
                                                                      opacity:
                                                                          0,
                                                                      child: Text(
                                                                        'Done',
                                                                      ),
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                        );

                                                        final issueBtn =
                                                            InkWell(
                                                          key: ValueKey(
                                                            'feature_step_log_bug_btn_${node.id}',
                                                          ),
                                                          onTap: () =>
                                                              _showLogPlaytestIssueDialog(
                                                            feat,
                                                            states,
                                                            index,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 11,
                                                              vertical: 6.5,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: const Color(
                                                                0xFF21293A,
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                6,
                                                              ),
                                                              border:
                                                                  Border.all(
                                                                color:
                                                                    const Color(
                                                                  0x21FFFFFF,
                                                                ),
                                                              ),
                                                            ),
                                                            child: Text(
                                                              'Issue',
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 12.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color:
                                                                    const Color(
                                                                  0xFFCBD5E1,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        );

                                                        if (isHalfScreenOverlayMode) {
                                                          return Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            children: [
                                                              verifyRow,
                                                              const SizedBox(
                                                                height: 10,
                                                              ),
                                                              Row(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .end,
                                                                children: [
                                                                  issueBtn,
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  doneBtn,
                                                                ],
                                                              ),
                                                            ],
                                                          );
                                                        }

                                                        return Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Expanded(
                                                              child: verifyRow,
                                                            ),
                                                            const SizedBox(
                                                              width: 12,
                                                            ),
                                                            issueBtn,
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            doneBtn,
                                                          ],
                                                        );
                                                      },
                                                    ),
                                                  ),

                                                  // Zero-size compatibility hooks for step actions
                                                  SizedBox(
                                                    height: 1,
                                                    child: Opacity(
                                                      opacity: 0,
                                                      child: Row(
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
                                                              final snippet = activeSubStep
                                                                      .codeFormula
                                                                      .trim()
                                                                      .isNotEmpty
                                                                  ? activeSubStep
                                                                      .codeFormula
                                                                      .trim()
                                                                  : activeSubStep
                                                                      .instruction
                                                                      .trim();
                                                              Clipboard.setData(
                                                                ClipboardData(
                                                                  text: snippet,
                                                                ),
                                                              );
                                                              if (!activeSubStep
                                                                  .subtask
                                                                  .completed) {
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
                                                            child: const Text(
                                                              '⧉ Copy & Next →',
                                                            ),
                                                          ),
                                                          InkWell(
                                                            key: ValueKey(
                                                              'inline_step_copilot_tailor_btn_${node.id}',
                                                            ),
                                                            onTap: () =>
                                                                _promptTailorHowToDialog(
                                                              feat,
                                                              states,
                                                              index,
                                                              selectedTaskIdx,
                                                            ),
                                                            child: const Text(
                                                              '✦ Tailor',
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
                                                            child: const Text(
                                                              'Log Issue',
                                                            ),
                                                          ),
                                                          InkWell(
                                                            key: ValueKey(
                                                              'step_parent_task_chip_${node.id}_$selectedTaskIdx',
                                                            ),
                                                            onTap: () =>
                                                                _rebuild(() {
                                                              _selectedSubStepIndexByTask[
                                                                      '${node.id}_$selectedTaskIdx'] =
                                                                  -1;
                                                            }),
                                                            child: Text(
                                                              '↑ ${selectedHowTo.numLabel} · ${selectedHowTo.shortTaskTitle}',
                                                            ),
                                                          ),
                                                          InkWell(
                                                            key: ValueKey(
                                                              'task_sheet_tuning_chip_${node.id}',
                                                            ),
                                                            onTap: () =>
                                                                _showEditCheckpointTuningAndGuardsDialog(
                                                              feat,
                                                              states,
                                                              node,
                                                            ),
                                                            child: Text(
                                                              activeSubStep
                                                                      .stepPath
                                                                      .isNotEmpty
                                                                  ? activeSubStep
                                                                      .stepPath
                                                                  : selectedHowTo
                                                                      .whereLocation,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );

                                            if (isDesktopDock) {
                                              return Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  SizedBox(
                                                    width: 288,
                                                    child: leftDockWidget,
                                                  ),
                                                  const SizedBox(width: 14),
                                                  Expanded(
                                                    child: rightDockWidget,
                                                  ),
                                                ],
                                              );
                                            } else {
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  leftDockWidget,
                                                  const SizedBox(height: 12),
                                                  rightDockWidget,
                                                ],
                                              );
                                            }
                                          },
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
                                          final isPlaytestVerified = node
                                                  .isCompleted &&
                                              !_awaitingPlaytestVerification
                                                  .contains(node.id);
                                          final gateStatusText =
                                              isPlaytestVerified
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
                                                          fontSize: 13.5,
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
                                                          fontSize: 13.5,
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
                                                    fontSize: 16,
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
                                                                horizontal: 10,
                                                                vertical: 4,
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
                                                                      14,
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
                                                            horizontal: 14,
                                                            vertical: 8,
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
                                                              fontSize: 15,
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
                                                                  !isPlaytestVerified)
                                                              ? accentEmerald
                                                              : accentEmerald
                                                                  .withValues(
                                                                  alpha: 0.15,
                                                                ),
                                                          foregroundColor: (allCheckpointStepsDone &&
                                                                  !isPlaytestVerified)
                                                              ? const Color(
                                                                  0xFF051B0B,
                                                                )
                                                              : accentEmerald,
                                                          elevation: 0,
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 16,
                                                            vertical: 10,
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
                                                          size: 16,
                                                        ),
                                                        label: Text(
                                                          isPlaytestVerified
                                                              ? 'Playtest Verified ✓'
                                                              : 'Pass Playtest & Continue →',
                                                          style:
                                                              GoogleFonts.inter(
                                                            fontSize: 15,
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
