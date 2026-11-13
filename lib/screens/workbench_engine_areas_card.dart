part of 'release_workbench_screen.dart';

class _ComponentInspectorVarRow {
  final String key;
  final String propertyLabel;
  final String categoryLabel;
  final String value;
  final List<String> usedInSteps;
  final int firstTaskIdx;
  final int firstSubStepIdx;
  final bool isUsedInActiveTask;
  final bool isUsedInActiveStep;
  final int? tuningParamIndex;

  const _ComponentInspectorVarRow({
    required this.key,
    required this.propertyLabel,
    required this.categoryLabel,
    required this.value,
    required this.usedInSteps,
    required this.firstTaskIdx,
    required this.firstSubStepIdx,
    required this.isUsedInActiveTask,
    required this.isUsedInActiveStep,
    this.tuningParamIndex,
  });
}

extension _WorkbenchEngineAreasExt on _ReleaseWorkbenchScreenState {
  /// Builds the node-scoped persistent variable list for `activeTargetComp`.
  /// - Only collects variables belonging to `activeTargetComp` (tasks targeting this node).
  /// - Variables belonging to other nodes in `components` are excluded so selecting a different
  ///   node in the Scene Tree switches the Inspector Dock to that node's own variables.
  /// - Within the selected node, variables remain in a stable list and focus/dim per step (`1.1`, `1.2`, etc.).
  List<_ComponentInspectorVarRow> _buildComponentInspectorRows({
    required FeatureStateNode node,
    required List<TaskHowToBlueprint> howToBlueprints,
    required int selectedTaskIdx,
    required int activeSubStepIdx,
    required ({
      String icon,
      String componentKey,
      String displayLabel,
    }) activeTargetComp,
    required List<({
      String icon,
      String componentKey,
      String displayLabel,
      List<int> taskIndices,
    })> components,
    required List<({String key, String value})> activeStepFallbackRows,
    required List<String> tuningItems,
    required String primaryTuningLabel,
    required bool is2D,
    required String archetype,
  }) {
    final activeCompLower = activeTargetComp.componentKey.toLowerCase();
    final matchedComp = components
        .where((c) => c.componentKey.toLowerCase() == activeCompLower)
        .toList();
    final List<int> compTaskIndices = matchedComp.isNotEmpty &&
            matchedComp.first.taskIndices.isNotEmpty
        ? matchedComp.first.taskIndices
        : <int>[selectedTaskIdx];

    final otherCompKeys = <String>{
      for (final c in components)
        if (c.componentKey.toLowerCase() != activeCompLower)
          c.componentKey.toLowerCase(),
    };

    final isActiveCapsuleComp = activeCompLower.contains('capsule') ||
        activeCompLower.contains('collider') ||
        activeCompLower.contains('collisionshape');
    final isActiveMovementComp = activeCompLower.contains('movement') ||
        activeCompLower.contains('rigidbody') ||
        activeCompLower.contains('characterbody');

    bool belongsToOtherComponent(String rawKey, String rawVal) {
      final keyLower = rawKey.toLowerCase();
      final valLower = rawVal.toLowerCase();
      if (isActiveCapsuleComp &&
          (keyLower == 'asset name' ||
              keyLower == 'parent class' ||
              keyLower.contains('walkspeed') ||
              keyLower.contains('move_speed') ||
              keyLower.contains('jump_velocity') ||
              keyLower.contains('air_control') ||
              valLower.contains('move_speed') ||
              valLower.contains('walkspeed'))) {
        return true;
      }
      final inferred = _inferOwningComponentForProperty(
        rawKey: rawKey,
        defaultComponentKey: activeTargetComp.componentKey,
        is2D: is2D,
      );
      final inferredCompLower = inferred.componentLabel.toLowerCase();
      if (inferredCompLower != activeCompLower) {
        if (otherCompKeys.contains(inferredCompLower) ||
            (isActiveCapsuleComp &&
                (inferredCompLower.contains('movement') ||
                    inferredCompLower.contains('camera') ||
                    inferredCompLower.contains('controller') ||
                    inferredCompLower.contains('characterbody'))) ||
            (isActiveMovementComp &&
                (inferredCompLower.contains('capsule') ||
                    inferredCompLower.contains('collider') ||
                    inferredCompLower.contains('collisionshape')))) {
          return true;
        }
      }
      return false;
    }

    final accumByNormKey = <String, ({
      String key,
      String propertyLabel,
      String categoryLabel,
      String value,
      List<String> usedInSteps,
      int firstTaskIdx,
      int firstSubStepIdx,
      int? tuningParamIndex,
    })>{};

    void recordProperty({
      required String rawKey,
      required String rawVal,
      required int tIdx,
      required int sIdx,
      int? explicitTuningIdx,
    }) {
      final cleanKey = rawKey.trim();
      final cleanVal = rawVal.trim();
      if (cleanKey.isEmpty || cleanVal.isEmpty) return;
      if (belongsToOtherComponent(cleanKey, cleanVal)) return;

      final resolved = _inferOwningComponentForProperty(
        rawKey: cleanKey,
        defaultComponentKey: activeTargetComp.componentKey,
        is2D: is2D,
      );
      final propLabel = resolved.propertyLabel.trim().isNotEmpty
          ? resolved.propertyLabel.trim()
          : cleanKey;
      final normKey = propLabel.toLowerCase();
      final stepBadge = '${tIdx + 1}.${sIdx + 1}';

      int? matchedTuningIdx = explicitTuningIdx;
      if (matchedTuningIdx == null) {
        for (int ti = 0; ti < tuningItems.length; ti++) {
          final tk = tuningItems[ti]
              .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
              .first
              .trim()
              .toLowerCase();
          if (tk.isNotEmpty &&
              (tk == normKey || tk == cleanKey.toLowerCase())) {
            matchedTuningIdx = ti;
            break;
          }
        }
      }

      String effectiveVal = cleanVal;
      if (matchedTuningIdx != null && matchedTuningIdx < tuningItems.length) {
        final tp = tuningItems[matchedTuningIdx];
        final parts =
            tp.split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex);
        if (parts.length > 1) {
          effectiveVal = parts.sublist(1).join(':').trim();
        }
      }
      final customOverride =
          _customComponentPropertyOverrides['${node.id}::$cleanKey'] ??
              _customComponentPropertyOverrides['${node.id}::$propLabel'];
      if (customOverride != null && customOverride.isNotEmpty) {
        effectiveVal = customOverride;
      }

      final existing = accumByNormKey[normKey];
      if (existing == null) {
        accumByNormKey[normKey] = (
          key: cleanKey,
          propertyLabel: propLabel,
          categoryLabel: resolved.categoryLabel,
          value: effectiveVal,
          usedInSteps: <String>[stepBadge],
          firstTaskIdx: tIdx,
          firstSubStepIdx: sIdx,
          tuningParamIndex: matchedTuningIdx,
        );
      } else {
        if (!existing.usedInSteps.contains(stepBadge)) {
          existing.usedInSteps.add(stepBadge);
        }
        if (tIdx == selectedTaskIdx && sIdx == activeSubStepIdx) {
          accumByNormKey[normKey] = (
            key: existing.key,
            propertyLabel: existing.propertyLabel,
            categoryLabel: existing.categoryLabel,
            value: effectiveVal,
            usedInSteps: existing.usedInSteps,
            firstTaskIdx: existing.firstTaskIdx,
            firstSubStepIdx: existing.firstSubStepIdx,
            tuningParamIndex:
                existing.tuningParamIndex ?? matchedTuningIdx,
          );
        }
      }
    }

    // 1. Collect properties across all sub-steps of tasks targeting `activeTargetComp`
    for (final tIdx in compTaskIndices) {
      if (tIdx < 0 || tIdx >= howToBlueprints.length) continue;
      final bp = howToBlueprints[tIdx];

      for (int sIdx = 0; sIdx < bp.subSteps.length; sIdx++) {
        final sub = bp.subSteps[sIdx];
        final aiArea2 = sub.area2Inspector?.trim() ?? '';
        bool addedAnyForSubStep = false;

        if (aiArea2.isNotEmpty) {
          final rawEntries = aiArea2.contains('\n')
              ? aiArea2.split('\n')
              : aiArea2.split('|');
          for (final rawEntry in rawEntries) {
            final cleanEntry = rawEntry.trim();
            if (cleanEntry.isEmpty) continue;
            final colonIdx = cleanEntry.indexOf(':');
            final eqIdx = cleanEntry.indexOf('=');
            final delimIdx = colonIdx != -1 ? colonIdx : eqIdx;
            if (delimIdx > 0 && delimIdx < cleanEntry.length - 1) {
              recordProperty(
                rawKey: cleanEntry.substring(0, delimIdx).trim(),
                rawVal: cleanEntry.substring(delimIdx + 1).trim(),
                tIdx: tIdx,
                sIdx: sIdx,
              );
              addedAnyForSubStep = true;
            }
          }
        }

        // Also check tuning parameters referenced in this sub-step's code or instruction
        final subCorpus =
            '${sub.shortTitle} ${sub.instruction} ${sub.codeFormula} $aiArea2'
                .toLowerCase();
        for (int ti = 0; ti < tuningItems.length; ti++) {
          final tp = tuningItems[ti].trim();
          if (tp.isEmpty) continue;
          final parts =
              tp.split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex);
          final k = parts.first.trim();
          final v =
              parts.length > 1 ? parts.sublist(1).join(':').trim() : '1.0';
          if (k.isNotEmpty && subCorpus.contains(k.toLowerCase())) {
            recordProperty(
              rawKey: k,
              rawVal: v,
              tIdx: tIdx,
              sIdx: sIdx,
              explicitTuningIdx: ti,
            );
            addedAnyForSubStep = true;
          }
        }

        if (!addedAnyForSubStep && sIdx == 0 && isActiveCapsuleComp) {
          recordProperty(
            rawKey: 'Height',
            rawVal: is2D ? '70.0 px' : '1.76 m',
            tIdx: tIdx,
            sIdx: sIdx,
          );
          recordProperty(
            rawKey: 'Radius',
            rawVal: is2D ? '16.0 px' : '0.35 m',
            tIdx: tIdx,
            sIdx: sIdx,
          );
        }
      }
    }

    // 2. Ensure all active-step fallback rows (for the selected component) are included
    for (final row in activeStepFallbackRows) {
      recordProperty(
        rawKey: row.key,
        rawVal: row.value,
        tIdx: selectedTaskIdx,
        sIdx: activeSubStepIdx,
      );
    }

    // 3. If a tuning item belongs to this component (or is the task's primary tuning slot) and isn't in the map yet, add it
    if (!isActiveCapsuleComp && tuningItems.isNotEmpty) {
      final slotIdx = selectedTaskIdx % tuningItems.length;
      final slotTp = tuningItems[slotIdx].trim();
      if (slotTp.isNotEmpty) {
        final parts =
            slotTp.split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex);
        final k = parts.first.trim();
        final v = parts.length > 1 ? parts.sublist(1).join(':').trim() : '1.0';
        if (k.isNotEmpty && !belongsToOtherComponent(k, v)) {
          recordProperty(
            rawKey: k,
            rawVal: v,
            tIdx: selectedTaskIdx,
            sIdx: 0,
            explicitTuningIdx: slotIdx,
          );
        }
      }
    }

    final activeStepBadge = '${selectedTaskIdx + 1}.${activeSubStepIdx + 1}';
    final activeTaskPrefix = '${selectedTaskIdx + 1}.';
    final rawEntries = accumByNormKey.values.toList();

    bool anyMatchesActiveStep = rawEntries
        .any((e) => e.usedInSteps.contains(activeStepBadge));

    final result = <_ComponentInspectorVarRow>[];
    for (int i = 0; i < rawEntries.length; i++) {
      final e = rawEntries[i];
      final usedInTask =
          e.usedInSteps.any((b) => b.startsWith(activeTaskPrefix));
      final usedInStep = e.usedInSteps.contains(activeStepBadge) ||
          (!anyMatchesActiveStep && i == 0);
      result.add(
        _ComponentInspectorVarRow(
          key: e.key,
          propertyLabel: e.propertyLabel,
          categoryLabel: e.categoryLabel,
          value: e.value,
          usedInSteps: e.usedInSteps,
          firstTaskIdx: e.firstTaskIdx,
          firstSubStepIdx: e.firstSubStepIdx,
          isUsedInActiveTask: usedInTask || usedInStep,
          isUsedInActiveStep: usedInStep,
          tuningParamIndex: e.tuningParamIndex,
        ),
      );
    }
    return result;
  }

  /// Renders the Godot 4 3-Area Step Card (`SCENE TREE DOCK (.tscn)`, `INSPECTOR DOCK`,
  /// `NODE SIGNALS`, and `GDSCRIPT`), showing only the sections
  /// genuinely used by the active step so Inspector setup is never mislabeled as GDScript.
  Widget _buildEngineStepAreasBox({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required FeatureStateNode node,
    required List<TaskHowToBlueprint> howToBlueprints,
    required TaskHowToBlueprint selectedHowTo,
    required TaskHowToSubStep activeSubStep,
    required int selectedTaskIdx,
    required int activeSubStepIdx,
    required String primaryTuningLabel,
    required String primaryGuardLabel,
    required List<String> tuningItems,
    required List<String> edgeItems,
  }) {
    final rawCode = activeSubStep.codeFormula.trim();
    final stepPath = activeSubStep.stepPath.isNotEmpty
        ? activeSubStep.stepPath
        : selectedHowTo.whereLocation;
    final primaryVarName = primaryTuningLabel
        .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
        .first
        .trim();

    // Strip any leading single-line comment when displaying a pure hierarchy/setup block
    final rawLines = rawCode.split('\n');
    final cleanSetupLines = <String>[];
    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i];
      if (i == 0 && line.trimLeft().startsWith('//')) continue;
      cleanSetupLines.add(line);
    }
    final cleanSetupText = cleanSetupLines.join('\n').trim().isEmpty
        ? rawCode
        : cleanSetupLines.join('\n').trim();

    // Classify the active step based on its actual content & step context
    final lowerPath = stepPath.toLowerCase();
    final hasSignalArrows = rawCode.contains('──►') ||
        rawCode.contains('└──►') ||
        rawCode.contains('├──►') ||
        RegExp(r'^\s*\[[^\]]+\]', multiLine: true).hasMatch(rawCode);
    final hasHierarchyTreeChars =
        RegExp(r'[└├]─(?!─►)').hasMatch(rawCode) && !hasSignalArrows;
    final isTreeHierarchyStep = !hasSignalArrows &&
        (hasHierarchyTreeChars ||
            lowerPath.contains('scene dock') ||
            lowerPath.contains('scene tree') ||
            lowerPath.contains('add child node'));
    final isLevelPlacementStep = !isTreeHierarchyStep &&
        (rawCode.contains('Instance:') ||
            rawCode.contains('Instanced Node:') ||
            lowerPath.contains('instantiate child scene') ||
            lowerPath.contains('main scene') ||
            (selectedTaskIdx == 0 && activeSubStepIdx == 2));
    final isCodeVariableStep = rawCode.contains('@export var') ||
        rawCode.contains('@export_range') ||
        lowerPath.contains('inspector');
    final isScriptCreationStep = selectedTaskIdx == 0 &&
        activeSubStepIdx == 0 &&
        !isTreeHierarchyStep &&
        !isCodeVariableStep;

    final matchedTunings = tuningItems.where((t) {
      final key = t
          .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
          .first
          .trim()
          .toLowerCase();
      return key.isNotEmpty &&
          (rawCode.toLowerCase().contains(key) ||
              activeSubStep.instruction.toLowerCase().contains(key));
    }).toList();
    final effectiveTuningLabel = matchedTunings.isNotEmpty
        ? matchedTunings.join('  ·  ')
        : primaryTuningLabel;

    String? compWhere;
    String? compBody;
    String inspWhere = '';
    final inspRows = <({String key, String value})>[];
    String? codeWhere;
    String? codeBody;

    if (isTreeHierarchyStep) {
      compWhere = stepPath;
      compBody = cleanSetupText;
      inspWhere = 'Inspector Dock (Node Properties)';
      for (final line in compBody.split('\n')) {
        final match = _ReleaseWorkbenchScreenState._treeChildRegex.firstMatch(line);
        if (match != null) {
          final nodeName = match.group(1)!.trim();
          final nodeDesc = (match.group(2) ?? '').trim();
          if (nodeName.isEmpty) continue;
          if (nodeDesc.isNotEmpty) {
            final colonIdx = nodeDesc.indexOf(':');
            if (colonIdx > 0 && colonIdx < nodeDesc.length - 1) {
              final propType = nodeDesc.substring(0, colonIdx).trim();
              final propVal = nodeDesc.substring(colonIdx + 1).trim();
              inspRows.add((
                key: '$nodeName → $propType',
                value: propVal,
              ));
            } else {
              inspRows.add((
                key: '$nodeName → Type / Resource',
                value: nodeDesc,
              ));
            }
          }
        }
      }
      for (final t in matchedTunings.take(2)) {
        final parts =
            t.split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex);
        final k = parts.first.trim();
        final v = parts.length > 1 ? parts.sublist(1).join(':').trim() : '1.0';
        if (k.isNotEmpty) {
          inspRows.add((key: 'Tuning · $k', value: v));
        }
      }
      if (inspRows.isEmpty) {
        inspRows.add((key: 'Primary Tuning Binding', value: effectiveTuningLabel));
      }
    } else if (isLevelPlacementStep) {
      compWhere = stepPath;
      compBody = cleanSetupText;
      inspWhere = 'Inspector Dock → Node Transform';
      inspRows.addAll(const [
        (
          key: 'Transform → Position',
          value: 'Vector2(0, 0) / Vector3(0, 0, 0)',
        ),
        (
          key: 'Scene Instance Mode',
          value: 'Active Level Instance',
        ),
      ]);
    } else if (isCodeVariableStep) {
      inspWhere = 'Inspector Dock → Script Variables';
      inspRows.addAll([
        (
          key: 'Inspector Specifier',
          value: '@export var',
        ),
        (key: 'Default Tuning Value', value: effectiveTuningLabel),
      ]);
      codeWhere = stepPath;
      codeBody = rawCode;
    } else if (isScriptCreationStep) {
      compWhere = 'Scene Dock (Top-Left)';
      compBody = 'Root Node (Node2D / CharacterBody2D/3D)  [📜 Attached .gd]';
      inspWhere = 'Script Attach Dialog';
      inspRows.addAll([
        const (
          key: 'Base Class',
          value: 'Node2D / Node3D',
        ),
        (key: 'File Path', value: stepPath),
      ]);
      codeWhere = stepPath;
      codeBody = rawCode;
    } else {
      // Runtime GDScript / Node Signals / Guard Step:
      if (activeSubStepIdx == 0) {
        inspWhere = activeSubStep.isGuardStep
            ? 'Guard Condition & Safety Check'
            : 'Runtime Tuning & Inspector Binding';
        inspRows.add((key: 'Tuning Parameter', value: effectiveTuningLabel));
      }
      codeWhere = stepPath;
      codeBody = rawCode;
    }

    final isPureRuntimeCodeStep = !isTreeHierarchyStep &&
        !isLevelPlacementStep &&
        !isCodeVariableStep &&
        !isScriptCreationStep &&
        activeSubStepIdx > 0;

    // Apply on-demand hierarchy & Inspector overrides when present
    final aiArea1 = activeSubStep.area1Hierarchy?.trim() ?? '';
    if (aiArea1.isNotEmpty) {
      compWhere ??= stepPath;
      compBody = aiArea1;
      if (rawCode.isNotEmpty && rawCode != aiArea1) {
        codeWhere ??= stepPath;
        codeBody ??= rawCode;
      }
    } else if (hasSignalArrows && rawCode.isNotEmpty) {
      codeWhere ??= stepPath;
      codeBody ??= rawCode;
    }
    final aiArea2 = activeSubStep.area2Inspector?.trim() ?? '';
    if (aiArea2.isNotEmpty) {
      if (inspWhere.isEmpty) {
        inspWhere = 'Inspector Dock';
      }
      final parsedAiRows = <({String key, String value})>[];
      final rawEntries = aiArea2.contains('\n')
          ? aiArea2.split('\n')
          : aiArea2.split('|');
      for (final rawEntry in rawEntries) {
        final cleanEntry = rawEntry.trim();
        if (cleanEntry.isEmpty) continue;
        final colonIdx = cleanEntry.indexOf(':');
        final eqIdx = cleanEntry.indexOf('=');
        final delimIdx = colonIdx != -1 ? colonIdx : eqIdx;
        if (delimIdx > 0 && delimIdx < cleanEntry.length - 1) {
          parsedAiRows.add((
            key: cleanEntry.substring(0, delimIdx).trim(),
            value: cleanEntry.substring(delimIdx + 1).trim(),
          ));
        } else {
          parsedAiRows.add((key: 'Inspector Binding', value: cleanEntry));
        }
      }
      final isSingleDuplicatePrimaryTuning = isPureRuntimeCodeStep &&
          aiArea1.isEmpty &&
          parsedAiRows.length == 1 &&
          parsedAiRows.first.key.toLowerCase() ==
              primaryVarName.toLowerCase();
      if (parsedAiRows.isNotEmpty && !isSingleDuplicatePrimaryTuning) {
        inspRows
          ..clear()
          ..addAll(parsedAiRows);
      }
    }

    if (compBody != null && compBody.trim().isNotEmpty && inspRows.isEmpty) {
      if (inspWhere.isEmpty) {
        inspWhere = compWhere ?? stepPath;
      }
      for (final rawLine in compBody.split('\n')) {
        final cleanLine = rawLine.trim();
        if (cleanLine.isEmpty) continue;
        inspRows.add((key: 'Node', value: cleanLine));
      }
    }

    final activeTargetComp = _resolveTaskTargetComponent(
      selectedHowTo,
    );
    final assetSpec = _resolveFeatureAssetSpec(
      feat: feat,
      checkpointIndex: checkpointIndex,
      selectedTaskIdx: selectedTaskIdx,
      selectedHowTo: selectedHowTo,
      activeSubStep: activeSubStep,
      activeTargetComp: activeTargetComp,
    );

    // ── Strict Task-Scoped Variable Filtering (Omit Unused Variables Completely) ──
    final taskTitleLower = selectedHowTo.shortTaskTitle.toLowerCase();
    final isTaskGuardRelevant = taskTitleLower.contains('guard') ||
        taskTitleLower.contains('clamp') ||
        taskTitleLower.contains('lock') ||
        taskTitleLower.contains('boundary') ||
        activeSubStep.stepNumberLabel.toUpperCase().contains('GUARD') ||
        selectedTaskIdx == howToBlueprints.length - 1 ||
        howToBlueprints.length == 1;

    final activeCompLower = activeTargetComp.componentKey.toLowerCase();
    final isActiveCapsuleTask = activeCompLower.contains('capsule') ||
        activeCompLower.contains('collider') ||
        activeCompLower.contains('collisionshape') ||
        taskTitleLower.contains('capsule') ||
        taskTitleLower.contains('collider');
    final isActiveMovementTask = activeCompLower.contains('movement') ||
        activeCompLower.contains('rigidbody') ||
        activeCompLower.contains('characterbody');

    final otherTaskCompKeys = <String>{
      for (int tIdx = 0; tIdx < howToBlueprints.length; tIdx++)
        if (tIdx != selectedTaskIdx)
          _resolveTaskTargetComponent(
            howToBlueprints[tIdx],
          ).componentKey.toLowerCase(),
    }..remove(activeCompLower);

    final taskExplicitCorpus = [
      selectedHowTo.shortTaskTitle,
      selectedHowTo.taskGoalSentence,
      activeSubStep.shortTitle,
      activeSubStep.codeFormula,
    ].join(' ').toLowerCase();

    final unfilteredInspRows = List<({String key, String value})>.from(inspRows);
    inspRows.removeWhere((row) {
      final keyLower = row.key.toLowerCase();
      final valLower = row.value.toLowerCase();
      if (!isTaskGuardRelevant && keyLower.contains('guard')) {
        return true;
      }
      if (isActiveCapsuleTask &&
          (keyLower == 'asset name' ||
              keyLower == 'parent class' ||
              keyLower.contains('walkspeed') ||
              keyLower.contains('move_speed') ||
              keyLower.contains('jump_velocity') ||
              keyLower.contains('air_control') ||
              valLower.contains('move_speed') ||
              valLower.contains('walkspeed'))) {
        return true;
      }
      final inferred = _inferOwningComponentForProperty(
        rawKey: row.key,
        defaultComponentKey: activeTargetComp.componentKey,
        is2D: assetSpec.is2D,
      );
      final inferredCompLower = inferred.componentLabel.toLowerCase();
      final propLower = inferred.propertyLabel.toLowerCase();
      if (inferredCompLower != activeCompLower) {
        final belongsToOtherTaskComp =
            otherTaskCompKeys.contains(inferredCompLower) ||
                (isActiveCapsuleTask &&
                    (inferredCompLower.contains('movement') ||
                        inferredCompLower.contains('camera') ||
                        inferredCompLower.contains('controller') ||
                        inferredCompLower.contains('characterbody'))) ||
                (isActiveMovementTask &&
                    (inferredCompLower.contains('capsule') ||
                        inferredCompLower.contains('collider') ||
                        inferredCompLower.contains('collisionshape')));
        if (belongsToOtherTaskComp && !taskExplicitCorpus.contains(propLower)) {
          return true;
        }
      }
      return false;
    });

    if (inspRows.isEmpty) {
      if (isActiveCapsuleTask) {
        inspRows.addAll([
          (
            key: 'Height',
            value: assetSpec.is2D ? '70.0 px' : '1.76 m',
          ),
          (
            key: 'Radius',
            value: assetSpec.is2D ? '16.0 px' : '0.35 m',
          ),
        ]);
      } else if (matchedTunings.isNotEmpty) {
        for (final t in matchedTunings.take(2)) {
          final parts =
              t.split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex);
          final k = parts.first.trim();
          final v =
              parts.length > 1 ? parts.sublist(1).join(':').trim() : '1.0';
          if (k.isNotEmpty) {
            inspRows.add((key: k, value: v));
          }
        }
      } else if (unfilteredInspRows.isNotEmpty) {
        inspRows.add(unfilteredInspRows.first);
      }
    }

    final components = _buildPersistentSceneTreeComponents(
      howToBlueprints,
    );

    final componentInspectorRows = _buildComponentInspectorRows(
      node: node,
      howToBlueprints: howToBlueprints,
      selectedTaskIdx: selectedTaskIdx,
      activeSubStepIdx: activeSubStepIdx,
      activeTargetComp: activeTargetComp,
      components: components,
      activeStepFallbackRows: inspRows,
      tuningItems: tuningItems,
      primaryTuningLabel: primaryTuningLabel,
      is2D: assetSpec.is2D,
      archetype: assetSpec.archetype,
    );

    final fallbackCodeLines = rawCode.isNotEmpty
        ? rawCode.split('\n')
        : <String>[
            for (final r in inspRows) '${r.key} = ${r.value}',
          ];
    final effectiveCodeLines =
        (codeBody != null && codeBody.trim().isNotEmpty)
            ? codeBody.split('\n')
            : fallbackCodeLines;
    final hasCode = effectiveCodeLines.isNotEmpty;
    final showCode =
        hasCode && (_engineAreaFilter == 0 || _engineAreaFilter == 3);
    final effectiveHeaderPath = (codeWhere != null && codeWhere.trim().isNotEmpty)
        ? codeWhere.trim()
        : stepPath;

    // ── INITIAL SETUP WIDGET (Option A: 3-Column Horizontal Strip · Only visible when assetSpec.isNewAssetOnTask == true) ──
    final Widget initialSetupWidget = assetSpec.isNewAssetOnTask
        ? Container(
            key: ValueKey('initial_setup_area_${node.id}'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF1E293B),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 9),
                  margin: const EdgeInsets.only(bottom: 9),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Color(0xFF161F2E),
                      ),
                    ),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Wrap(
                        spacing: 7,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'INITIAL SETUP',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: fontMicro,
                              fontWeight: weightBold,
                              letterSpacing: 0.4,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                          Text(
                            '·',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: fontMicro,
                              fontWeight: weightSemi,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          Text(
                            '${assetSpec.assetIcon} ${assetSpec.assetName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: fontBody,
                              fontWeight: weightBold,
                              color: const Color(0xFF38BDF8),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF131B28),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF243046),
                              ),
                            ),
                            child: Text(
                              assetSpec.parentClassLabel,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: fontMicro,
                                fontWeight: weightSemi,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF131B28),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFF243046),
                          ),
                        ),
                        child: Text(
                          '+ Create in ${assetSpec.folderPath}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: fontMicro,
                            fontWeight: weightSemi,
                            color: const Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                LayoutBuilder(
                  builder: (context, setupCons) {
                    final useHorizontalGrid =
                        setupCons.maxWidth >= 560 &&
                        assetSpec.setupSteps.length > 1;
                    Widget buildSetupStepCard(int stIdx) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E1420),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF182234),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${stIdx + 1}. ${assetSpec.setupSteps[stIdx].label}:',
                              style: GoogleFonts.inter(
                                fontSize: fontBody,
                                fontWeight: weightBold,
                                height: 1.4,
                                color: const Color(0xFFF8FAFC),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text.rich(
                              _buildSemanticStepSpan(
                                text: assetSpec.setupSteps[stIdx].detail,
                                baseStyle: GoogleFonts.inter(
                                  fontSize: fontBody,
                                  fontWeight: weightRegular,
                                  height: 1.4,
                                  color: const Color(0xFF94A3B8),
                                ),
                                tuningItems: tuningItems,
                                edgeItems: edgeItems,
                                isCodeBlock: false,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (useHorizontalGrid) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int stIdx = 0;
                                stIdx < assetSpec.setupSteps.length;
                                stIdx++) ...[
                              if (stIdx > 0) const SizedBox(width: 8),
                              Expanded(child: buildSetupStepCard(stIdx)),
                            ],
                          ],
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int stIdx = 0;
                            stIdx < assetSpec.setupSteps.length;
                            stIdx++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: stIdx == assetSpec.setupSteps.length - 1
                                  ? 0
                                  : 6,
                            ),
                            child: buildSetupStepCard(stIdx),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          )
        : SizedBox.shrink(
            key: ValueKey('initial_setup_area_${node.id}'),
          );

    // Count completed sub-steps for the active task
    final int activeTaskDoneSteps = selectedHowTo.subSteps
        .where((s) => s.subtask.completed)
        .length;

    bool isSubStepExpanded(int stepIdx) {
      final stepKey = '${node.id}_${selectedTaskIdx}_$stepIdx';
      if (_collapsedSubStepKeys.contains(stepKey)) return false;
      if (_expandedSubStepKeys.contains(stepKey)) return true;
      if (widget.workbench.focusMode && selectedHowTo.subSteps.length > 1) {
        return stepIdx == activeSubStepIdx;
      }
      return true;
    }

    final compactHierarchySummary = components.isNotEmpty
        ? components
            .take(3)
            .map((c) => c.displayLabel)
            .join(' › ')
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ══════════════════════════════════════════════════════════════════════
        // 100% FULL-WIDTH RUNBOOK SHEET:
        //   1. INITIAL SETUP (only when assetSpec.isNewAssetOnTask == true)
        //   2. STEPS (X/Y) + TARGET + Hierarchy Summary + Focus/Expand All
        //   3. Focus-Mode Step → Code Accordion (1.1, 1.2, 1.3)
        // ══════════════════════════════════════════════════════════════════════
        Padding(
          key: ValueKey('area3_script_setup_panel_${node.id}'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. INITIAL SETUP (Only shown when assetSpec.isNewAssetOnTask == true) ──
              initialSetupWidget,
              if (assetSpec.isNewAssetOnTask) const SizedBox(height: 14),

              // ── 2. STEPS (X/Y) + TARGET + COMPACT HIERARCHY HEADER BAR ──
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF181E2C),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFF262E40),
                          ),
                        ),
                        child: Text(
                          'STEPS ($activeTaskDoneSteps/${selectedHowTo.subSteps.length})',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: fontMicro,
                            fontWeight: weightBold,
                            letterSpacing: 0.4,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B0E15),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: const Color(0xFF262E40),
                          ),
                        ),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'TARGET: ',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: fontMicro,
                                  fontWeight: weightBold,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              TextSpan(
                                text:
                                    '${assetSpec.assetIcon} ${assetSpec.assetName}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: fontMicro,
                                  fontWeight: weightSemi,
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              TextSpan(
                                text: ' › ',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: fontMicro,
                                  fontWeight: weightSemi,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              TextSpan(
                                text:
                                    '${activeTargetComp.icon} ${activeTargetComp.displayLabel}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: fontMicro,
                                  fontWeight: weightSemi,
                                  color: const Color(0xFF38BDF8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (compactHierarchySummary.isNotEmpty)
                        Container(
                          key: ValueKey(
                            'steps_hierarchy_summary_${node.id}_$selectedTaskIdx',
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF090D15),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                          child: Text(
                            'Hierarchy: $compactHierarchySummary',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: weightRegular,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      if (selectedHowTo.subSteps.length > 1)
                        Builder(
                          builder: (context) {
                            final allExpanded = List<int>.generate(
                              selectedHowTo.subSteps.length,
                              (i) => i,
                            ).every(isSubStepExpanded);
                            return InkWell(
                              key: ValueKey(
                                'toggle_all_substeps_btn_${node.id}_$selectedTaskIdx',
                              ),
                              borderRadius: BorderRadius.circular(5),
                              onTap: () {
                                _rebuild(() {
                                  for (int i = 0;
                                      i < selectedHowTo.subSteps.length;
                                      i++) {
                                    final k =
                                        '${node.id}_${selectedTaskIdx}_$i';
                                    if (allExpanded) {
                                      if (widget.workbench.focusMode &&
                                          i == activeSubStepIdx) {
                                        _collapsedSubStepKeys.remove(k);
                                        _expandedSubStepKeys.add(k);
                                      } else {
                                        _expandedSubStepKeys.remove(k);
                                        _collapsedSubStepKeys.add(k);
                                      }
                                    } else {
                                      _collapsedSubStepKeys.remove(k);
                                      _expandedSubStepKeys.add(k);
                                    }
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF131926),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: const Color(0xFF262E40),
                                  ),
                                ),
                                child: Text(
                                  allExpanded
                                      ? (widget.workbench.focusMode
                                          ? '▴ Focus Active'
                                          : 'Collapse all')
                                      : '▾ Expand All',
                                  style: GoogleFonts.inter(
                                    fontSize: fontMicro,
                                    fontWeight: weightSemi,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  InkWell(
                    key: ValueKey(
                      'copy_task_ai_prompt_btn_${node.id}_$selectedTaskIdx',
                    ),
                    onTap: () {
                      final inspSummary = componentInspectorRows
                          .map((r) => '- ${r.propertyLabel}: ${r.value}')
                          .join('\n');
                      final setupSummary = [
                        for (int i = 0; i < assetSpec.setupSteps.length; i++)
                          '${i + 1}. ${assetSpec.setupSteps[i].label}: ${assetSpec.setupSteps[i].detail}',
                      ].join('\n');
                      final levelSummary = [
                        for (int i = 0;
                            i < assetSpec.levelHookupSteps.length;
                            i++)
                          '${i + 1}. ${assetSpec.levelHookupSteps[i]}',
                      ].join('\n');
                      final allSubStepsPrompt = [
                        for (int i = 0;
                            i < selectedHowTo.subSteps.length;
                            i++) ...[
                          () {
                            final st = selectedHowTo.subSteps[i];
                            final stPath = st.stepPath.trim().isNotEmpty
                                ? st.stepPath.trim()
                                : effectiveHeaderPath;
                            final stHier = (st.area1Hierarchy ?? '').trim();
                            final stInsp = (st.area2Inspector ?? '').trim();
                            final stCode = st.codeFormula.trim();
                            final stCheck = st.verifyResult.trim();
                            return [
                              '### Step ${selectedTaskIdx + 1}.${i + 1} · ${st.shortTitle} ($stPath)',
                              if (st.instruction.trim().isNotEmpty)
                                'DO: ${st.instruction.trim()}',
                              if (stHier.isNotEmpty) 'Hierarchy:\n$stHier',
                              if (stInsp.isNotEmpty) 'Inspector: $stInsp',
                              if (stCode.isNotEmpty) 'Script:\n$stCode',
                              if (stCheck.isNotEmpty)
                                '${st.isEditorCheck ? 'Check in Editor' : 'Verify in Engine'}: $stCheck',
                            ].join('\n');
                          }(),
                        ],
                      ].join('\n\n');
                      final tuningSummary = tuningItems.isNotEmpty
                          ? tuningItems.map((t) => '- $t').join('\n')
                          : '';
                      final guardsSummary = edgeItems.isNotEmpty
                          ? edgeItems.map((g) => '- $g').join('\n')
                          : (primaryGuardLabel.isNotEmpty
                              ? '- $primaryGuardLabel'
                              : '');
                      final promptText = [
                        'Task T${selectedTaskIdx + 1}: ${selectedHowTo.shortTaskTitle} (${feat.title})',
                        'Asset: ${assetSpec.assetName} (${assetSpec.parentClassLabel}) in ${assetSpec.folderPath}',
                        if (setupSummary.isNotEmpty)
                          'Setup Steps:\n$setupSummary',
                        'Target Component: ${activeTargetComp.displayLabel}',
                        if (tuningSummary.isNotEmpty)
                          'Tuning Parameters:\n$tuningSummary',
                        if (inspSummary.isNotEmpty)
                          'Inspector Properties:\n$inspSummary',
                        if (guardsSummary.isNotEmpty)
                          'Guardrails:\n$guardsSummary',
                        if (allSubStepsPrompt.isNotEmpty)
                          'Implementation Steps (${selectedHowTo.subSteps.length}):\n$allSubStepsPrompt',
                        if (levelSummary.isNotEmpty)
                          '${assetSpec.levelHookupTitle}:\n$levelSummary',
                        'Task Verify Goal: ${selectedHowTo.taskDoneCheck}',
                      ].join('\n\n');
                      Clipboard.setData(
                        ClipboardData(text: promptText),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Copied Task T${selectedTaskIdx + 1} AI Prompt (${selectedHowTo.subSteps.length} steps)',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181E2C),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF262E40),
                        ),
                      ),
                      child: Text(
                        '✦ Copy Task Prompt',
                        style: GoogleFonts.inter(
                          fontSize: fontMicro,
                          fontWeight: weightSemi,
                          color: const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── 3. OPTION A: ALL-STEPS-OPEN STEP → CODE STACK (`1.1`, `1.2`, `1.3`) ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int sIdx = 0;
                      sIdx < selectedHowTo.subSteps.length;
                      sIdx++)
                    Builder(
                      builder: (context) {
                        final subStep = selectedHowTo.subSteps[sIdx];
                        final bool isSubActive = sIdx == activeSubStepIdx;
                        final bool isSubDone = subStep.subtask.completed;
                        final String stepCollapseKey =
                            '${node.id}_${selectedTaskIdx}_$sIdx';
                        final bool isStepExpanded = isSubStepExpanded(sIdx);
                        final String stepRawCode = subStep.codeFormula.trim();
                        final List<String> stepCodeLines =
                            stepRawCode.isNotEmpty
                                ? stepRawCode.split('\n')
                                : const <String>[];
                        final List<String> rawPipeTableLines = stepCodeLines
                            .where(
                              (l) =>
                                  l.trim().startsWith('|') &&
                                  l.trim().endsWith('|'),
                            )
                            .toList();
                        final String stepDoInstruction =
                            subStep.instruction.trim();
                        final String stepPathBadgeText =
                            subStep.stepPath.trim();
                        final String stepVerifyText =
                            subStep.verifyResult.trim();
                        final List<String> effectiveTableLines =
                            rawPipeTableLines.length >= 2
                                ? rawPipeTableLines
                                : _tryConvertConfigGraphToTableLines(
                                    stepRawCode,
                                    stepDo: stepDoInstruction,
                                    stepRole: subStep.stepRole ?? '',
                                    defaultTarget: activeTargetComp.displayLabel,
                                  );
                        final windowCtx = _resolveWindowContextForSubStep(
                          subStep,
                          activeTargetLabel: activeTargetComp.displayLabel,
                        );
                        final prevWindowCtx = sIdx > 0
                            ? _resolveWindowContextForSubStep(
                                selectedHowTo.subSteps[sIdx - 1],
                                activeTargetLabel:
                                    activeTargetComp.displayLabel,
                              )
                            : null;
                        final bool isWindowContextSwitch =
                            prevWindowCtx != null &&
                                prevWindowCtx.label != windowCtx.label;

                        // Resolve conditional Guard chip only when directly relevant to this step
                        String stepGuardChipText = '';
                        if (edgeItems.isNotEmpty) {
                          final bool mentionsGuardConcept =
                              subStep.isGuardStep ||
                                  RegExp(
                                    r'\b(?:guard|clamp|cooldown|null|is_valid|invalid|limit|prevent|cap)\b',
                                    caseSensitive: false,
                                  ).hasMatch(
                                    '${subStep.shortTitle} $stepDoInstruction $stepRawCode',
                                  );
                          if (mentionsGuardConcept) {
                            stepGuardChipText = edgeItems.first
                                .replaceFirst(
                                  RegExp(
                                    r'^\[(?:STATE|PLAYTEST)?\s*GUARD\]\s*',
                                    caseSensitive: false,
                                  ),
                                  '',
                                )
                                .trim();
                          }
                        }
                        final bool hasStepEditorContext =
                            stepGuardChipText.isNotEmpty;
                        final bool hasExpandableDrawerContent =
                            stepDoInstruction.isNotEmpty ||
                                hasStepEditorContext ||
                                (showCode &&
                                    (stepCodeLines.isNotEmpty ||
                                        effectiveTableLines.isNotEmpty)) ||
                                stepVerifyText.isNotEmpty;

                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: sIdx == selectedHowTo.subSteps.length - 1
                                ? 0
                                : 10,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSubActive
                                  ? const Color(0xFF141B29)
                                  : const Color(0xFF0D131F),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSubActive
                                    ? const Color(0xFF38BDF8)
                                        .withValues(alpha: 0.48)
                                    : const Color(0xFF24324B),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Step Header Row (Checkbox + 1.X + Short Title + Step Path + [✎] + [Copy code] + Fold Chevron)
                                InkWell(
                                  key: ValueKey(
                                    'task_sheet_step_row_${node.id}_${selectedTaskIdx}_$sIdx',
                                  ),
                                  onTap: () {
                                    _rebuild(() {
                                      _selectedSubStepIndexByTask[
                                          '${node.id}_$selectedTaskIdx'] = sIdx;
                                      _collapsedSubStepKeys
                                          .remove(stepCollapseKey);
                                      _expandedSubStepKeys.add(stepCollapseKey);
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    child: Row(
                                      children: [
                                        // Step Completion Checkbox
                                        InkWell(
                                          key: ValueKey(
                                            'toggle_step_mark_${node.id}_${selectedTaskIdx}_$sIdx',
                                          ),
                                          onTap: () =>
                                              _toggleHowToSubStepCompletion(
                                            feat,
                                            states,
                                            node,
                                            selectedTaskIdx,
                                            sIdx,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Container(
                                            width: 18,
                                            height: 18,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: isSubDone
                                                  ? const Color(0xFF10B981)
                                                  : const Color(0xFF07090E),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: isSubDone
                                                    ? const Color(0xFF10B981)
                                                    : (isSubActive
                                                        ? const Color(
                                                            0xFF38BDF8)
                                                        : const Color(
                                                            0xFF334155)),
                                              ),
                                            ),
                                            child: Text(
                                              isSubDone ? '✓' : '',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: fontMicro,
                                                fontWeight: weightBold,
                                                height: 1.0,
                                                color: const Color(0xFF05101A),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        SizedBox(
                                          width: 32,
                                          child: Text(
                                            '${selectedTaskIdx + 1}.${sIdx + 1}',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: fontBody,
                                              fontWeight: weightBold,
                                              color: const Color(0xFF38BDF8),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  subStep.shortTitle,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.inter(
                                                    fontSize: fontItem,
                                                    fontWeight: weightBold,
                                                    color: isSubActive
                                                        ? const Color(
                                                            0xFFF8FAFC)
                                                        : const Color(
                                                            0xFFE2E8F0),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                key: ValueKey(
                                                  'window_context_badge_${node.id}_${selectedTaskIdx}_$sIdx',
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 1.5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: windowCtx.accent
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: windowCtx.accent
                                                        .withValues(
                                                      alpha: 0.36,
                                                    ),
                                                  ),
                                                ),
                                                child: Text(
                                                  '${windowCtx.icon} ${windowCtx.label}',
                                                  style: GoogleFonts
                                                      .jetBrainsMono(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                    color: windowCtx.accent,
                                                  ),
                                                ),
                                              ),
                                              if (!isStepExpanded) ...[
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '${_summarizeSubStepForCollapsedRow(subStep, rawTableLines: rawPipeTableLines)} · ▾ Re-open',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 9.5,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: const Color(
                                                        0xFF64748B,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ] else if (stepPathBadgeText
                                                  .isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFF090D16,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFF1E293B,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      stepPathBadgeText,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: const Color(
                                                          0xFF64748B,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        InkWell(
                                          key: ValueKey(
                                            'edit_howto_substep_${node.id}_${selectedTaskIdx}_$sIdx',
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          onTap: () =>
                                              _promptEditHowToSubStepDialog(
                                            feat,
                                            states,
                                            node,
                                            selectedTaskIdx,
                                            sIdx,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF131B2A),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: const Color(0xFF24324B),
                                              ),
                                            ),
                                            child: Text(
                                              '✎',
                                              style: GoogleFonts.inter(
                                                fontSize: fontMicro,
                                                color: const Color(0xFF94A3B8),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        InkWell(
                                          key: ValueKey(
                                            'copy_howto_code_${node.id}_${selectedTaskIdx}_$sIdx',
                                          ),
                                          onTap: () =>
                                              _copySubStepCodeFormula(
                                            selectedTaskIdx,
                                            sIdx,
                                            subStep.codeFormula,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          child: Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF162032),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color:
                                                    const Color(0xFF283854),
                                              ),
                                            ),
                                            child: Text(
                                              assetSpec.archetype == 'level'
                                                  ? '⧉ Copy steps'
                                                  : '⧉ Copy code',
                                              style: GoogleFonts.inter(
                                                fontSize: fontMicro,
                                                fontWeight: weightSemi,
                                                color:
                                                    const Color(0xFFCBD5E1),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        InkWell(
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          onTap: () {
                                            _rebuild(() {
                                              if (isStepExpanded) {
                                                _expandedSubStepKeys
                                                    .remove(stepCollapseKey);
                                                _collapsedSubStepKeys
                                                    .add(stepCollapseKey);
                                              } else {
                                                _collapsedSubStepKeys
                                                    .remove(stepCollapseKey);
                                                _expandedSubStepKeys
                                                    .add(stepCollapseKey);
                                              }
                                            });
                                          },
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              isStepExpanded
                                                  ? Icons
                                                      .keyboard_arrow_up_rounded
                                                  : Icons
                                                      .keyboard_arrow_down_rounded,
                                              size: 18,
                                              color: isSubActive
                                                  ? const Color(0xFF38BDF8)
                                                  : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Expanded 3-Area Implementation Drawer (DO + Conditional Editor Context + Code + Per-Step Check)
                                if (isStepExpanded &&
                                    hasExpandableDrawerContent)
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      10,
                                      14,
                                      10,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF07090E),
                                      border: Border(
                                        top: BorderSide(
                                          color: Color(0xFF182234),
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // 0. Context-Switch Callout (only when moving to a different Godot Dock)
                                        if (isWindowContextSwitch)
                                          Container(
                                            key: ValueKey(
                                              'window_context_switch_${node.id}_${selectedTaskIdx}_$sIdx',
                                            ),
                                            margin: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: windowCtx.accent
                                                  .withValues(alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: windowCtx.accent
                                                    .withValues(alpha: 0.25),
                                              ),
                                            ),
                                            child: Text(
                                              '↳ Switch from ${prevWindowCtx.icon} ${prevWindowCtx.label} to ${windowCtx.icon} ${windowCtx.label}',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: windowCtx.accent,
                                              ),
                                            ),
                                          ),
                                        // 1-4. Responsive 2-Column Workbook Spread (Left: DO + Guard + Check | Right: Godot Panel)
                                        _buildStepDrawerBody(
                                          nodeId: node.id,
                                          selectedTaskIdx: selectedTaskIdx,
                                          sIdx: sIdx,
                                          subStep: subStep,
                                          windowCtx: windowCtx,
                                          showCode: showCode,
                                          isDark: isDark,
                                          stepDoInstruction: stepDoInstruction,
                                          stepGuardChipText: stepGuardChipText,
                                          effectiveTableLines:
                                              effectiveTableLines,
                                          stepRawCode: stepRawCode,
                                          stepCodeLines: stepCodeLines,
                                          stepPathBadgeText: stepPathBadgeText,
                                          stepVerifyText: stepVerifyText,
                                          assetName: assetSpec.assetName,
                                          parentClassLabel:
                                              assetSpec.parentClassLabel,
                                          tuningItems: tuningItems,
                                          edgeItems: edgeItems,
                                          fontMicro: fontMicro,
                                          fontBody: fontBody,
                                          weightRegular: weightRegular,
                                          weightSemi: weightSemi,
                                          weightBold: weightBold,
                                          textPrimary: textPrimary,
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Styles Tuning Variable Names (Violet), Guard Rules (Amber), and Concrete Assets/Components (Cyan)
  /// directly inline using colored monospace font (`JetBrains Mono`, `FontWeight.w700`, zero boxes).
  TextSpan _buildSemanticStepSpan({
    required String text,
    required TextStyle baseStyle,
    required List<String> tuningItems,
    required List<String> edgeItems,
    required bool isCodeBlock,
  }) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    // Multi-token GDScript / GDExtension C++ Syntax Highlighting for Code Blocks:
    // - Comments (#..., //..., /*...*/): #8B949E italic
    // - Annotations & Godot types (@export, Vector2/3, CharacterBody2D/3D, etc.): #79C0FF
    // - Methods & built-in functions (move_and_slide(), or identifier before '('): #D2A8FF
    // - Numeric/boolean literals (8.5, false, true, null): #FFA657
    if (isCodeBlock && isDark) {
      final codeSyntaxRegex = RegExp(
        r'(?<comment>//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*)|'
        r'(?<arrow>[└├]?──►)|'
        r'(?<literal>\b(?:true|false|nullptr|null|PI|TAU|INF|NAN)\b|(?<![A-Za-z0-9_])-?\d+(?:\.\d+)?f?\b)|'
        r'(?<type>@[A-Za-z_][A-Za-z0-9_]*|\b(?:Vector2|Vector3|Vector2i|Vector3i|Color|Transform2D|Transform3D|Basis|Quaternion|CharacterBody2D|CharacterBody3D|RigidBody2D|RigidBody3D|StaticBody2D|StaticBody3D|Area2D|Area3D|RayCast2D|RayCast3D|CollisionShape2D|CollisionShape3D|Camera2D|Camera3D|Marker2D|Marker3D|Node2D|Node3D|Node|Control|CanvasLayer|ProgressBar|Label|Button|Line2D|Sprite2D|AnimatedSprite2D|MeshInstance3D|AudioStreamPlayer|AudioStreamPlayer2D|AudioStreamPlayer3D|Timer|Input|InputEvent|Engine|Resource|PackedScene|String|StringName|Array|Dictionary|Callable|Signal|Tween|SceneTree|GDCLASS|ClassDB|void|float|double|int|bool|auto|const|var|func|signal|extends|class_name|self|super|match|await|return|if|elif|else|for|in|while|and|or|not|preload|load)\b)|'
        r'(?<method>\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\())',
      );

      final baseFontSize = baseStyle.fontSize ?? fontBody;
      final codeSpans = <InlineSpan>[];
      int codeCursor = 0;
      for (final match in codeSyntaxRegex.allMatches(text)) {
        if (match.start > codeCursor) {
          codeSpans.add(
            TextSpan(text: text.substring(codeCursor, match.start)),
          );
        }
        final token = match.group(0)!;
        Color tokenColor = const Color(0xFFE6EDF3);
        FontStyle tokenFontStyle = FontStyle.normal;
        if (match.namedGroup('comment') != null) {
          tokenColor = const Color(0xFF8B949E);
          tokenFontStyle = FontStyle.italic;
        } else if (match.namedGroup('arrow') != null) {
          tokenColor = const Color(0xFFD2A8FF);
        } else if (match.namedGroup('literal') != null) {
          tokenColor = const Color(0xFFFFA657);
        } else if (match.namedGroup('type') != null) {
          tokenColor = const Color(0xFF79C0FF);
        } else if (match.namedGroup('method') != null) {
          tokenColor = const Color(0xFFD2A8FF);
        }
        codeSpans.add(
          TextSpan(
            text: token,
            style: GoogleFonts.jetBrainsMono(
              fontSize: baseFontSize,
              fontWeight: weightRegular,
              fontStyle: tokenFontStyle,
              color: tokenColor,
              height: baseStyle.height,
            ),
          ),
        );
        codeCursor = match.end;
      }
      if (codeCursor < text.length) {
        codeSpans.add(TextSpan(text: text.substring(codeCursor)));
      }
      return TextSpan(
        style: baseStyle,
        children: codeSpans,
      );
    }

    final specKey = '${tuningItems.join('\u0001')}\u0002${edgeItems.join('\u0001')}';
    if (specKey != _ReleaseWorkbenchScreenState._cachedSpecTokenKey) {
      final baseMap = <String, String>{};
      // 1. Tuning variable identifiers & full tuning specs -> 'tune' (Violet)
      for (final rawTune in tuningItems) {
        final trimmed = rawTune.trim();
        if (trimmed.isNotEmpty) {
          baseMap[trimmed] = 'tune';
          final varName = trimmed
              .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
              .first
              .trim();
          if (varName.length >= 3) {
            baseMap[varName] = 'tune';
          }
        }
      }
      // 2. Concrete guard variables, conditions & guard rules -> 'guard' (Amber)
      for (final guardToken
          in TaskHowToBlueprint.extractGuardHighlightTokens(edgeItems)) {
        baseMap[guardToken] = 'guard';
      }
      _ReleaseWorkbenchScreenState._cachedSpecTokenKey = specKey;
      _ReleaseWorkbenchScreenState._cachedBaseTokens = baseMap;
      if (baseMap.isEmpty) {
        _ReleaseWorkbenchScreenState._cachedBaseTokenRegex = null;
      } else {
        final sortedBase = baseMap.keys.toList()
          ..sort((a, b) => b.length.compareTo(a.length));
        _ReleaseWorkbenchScreenState._cachedBaseTokenRegex =
            RegExp(sortedBase.map(RegExp.escape).join('|'));
      }
    }

    final baseTokens = _ReleaseWorkbenchScreenState._cachedBaseTokens;
    Map<String, String> tokenKindByLiteral = baseTokens;
    RegExp? combinedRegex = _ReleaseWorkbenchScreenState._cachedBaseTokenRegex;

    // 3. Concrete asset & component names -> 'asset' (Cyan)
    final assetMatches =
        _ReleaseWorkbenchScreenState._assetTokenRegex.allMatches(text);
    if (assetMatches.isNotEmpty) {
      Map<String, String>? merged;
      for (final m in assetMatches) {
        final matchStr = m.group(0)!;
        if (!tokenKindByLiteral.containsKey(matchStr)) {
          merged ??= Map<String, String>.from(baseTokens);
          merged[matchStr] = 'asset';
        }
      }
      if (merged != null) {
        tokenKindByLiteral = merged;
        final sortedTokens = tokenKindByLiteral.keys.toList()
          ..sort((a, b) => b.length.compareTo(a.length));
        combinedRegex = RegExp(sortedTokens.map(RegExp.escape).join('|'));
      }
    }

    if (tokenKindByLiteral.isEmpty || combinedRegex == null) {
      return TextSpan(text: text, style: baseStyle);
    }

    final baseFontSize = baseStyle.fontSize ?? fontBody;
    final monoSize = baseFontSize;

    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final match in combinedRegex.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: text.substring(cursor, match.start),
          ),
        );
      }
      final matchedText = match.group(0)!;
      spans.add(
        TextSpan(
          text: matchedText,
          style: GoogleFonts.jetBrainsMono(
            fontSize: monoSize,
            fontWeight: isCodeBlock ? weightRegular : weightSemi,
            color: accentCyan,
            height: baseStyle.height,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(cursor),
        ),
      );
    }

    return TextSpan(
      style: baseStyle,
      children: spans,
    );
  }

  Widget _buildStepDrawerBody({
    required String nodeId,
    required int selectedTaskIdx,
    required int sIdx,
    required TaskHowToSubStep subStep,
    required ({String icon, String label, Color accent}) windowCtx,
    required bool showCode,
    required bool isDark,
    required String stepDoInstruction,
    required String stepGuardChipText,
    required List<String> effectiveTableLines,
    required String stepRawCode,
    required List<String> stepCodeLines,
    required String stepPathBadgeText,
    required String stepVerifyText,
    required String assetName,
    required String parentClassLabel,
    required List<String> tuningItems,
    required List<String> edgeItems,
    required double fontMicro,
    required double fontBody,
    required FontWeight weightRegular,
    required FontWeight weightSemi,
    required FontWeight weightBold,
    required Color textPrimary,
  }) {
    final doItems = _parseDoActionItems(stepDoInstruction);
    final Widget? doWidget = doItems.isNotEmpty
        ? _buildVerticalDoList(
            nodeId: nodeId,
            selectedTaskIdx: selectedTaskIdx,
            sIdx: sIdx,
            items: doItems,
            tuningItems: tuningItems,
            edgeItems: edgeItems,
            fontMicro: fontMicro,
            fontBody: fontBody,
            weightRegular: weightRegular,
            weightBold: weightBold,
          )
        : null;

    final Widget? guardWidget = stepGuardChipText.isNotEmpty
        ? Align(
            alignment: Alignment.centerLeft,
            child: Container(
              key: ValueKey(
                'step_guard_pill_${nodeId}_${selectedTaskIdx}_$sIdx',
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1D160B),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.36),
                ),
              ),
              child: Text(
                '🛡 $stepGuardChipText',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: fontMicro,
                  fontWeight: weightSemi,
                  color: const Color(0xFFFCD34D),
                ),
              ),
            ),
          )
        : null;

    final Widget? checkFooter = stepVerifyText.isNotEmpty
        ? _buildStepCheckFooter(
            nodeId: nodeId,
            selectedTaskIdx: selectedTaskIdx,
            sIdx: sIdx,
            subStep: subStep,
            stepVerifyText: stepVerifyText,
            tuningItems: tuningItems,
            edgeItems: edgeItems,
            fontMicro: fontMicro,
            weightRegular: weightRegular,
            weightBold: weightBold,
          )
        : null;

    final Widget? rightVisual = showCode
        ? _buildStepRightVisualPane(
            isDark: isDark,
            effectiveTableLines: effectiveTableLines,
            stepRawCode: stepRawCode,
            stepCodeLines: stepCodeLines,
            stepPathBadgeText: stepPathBadgeText,
            windowCtx: windowCtx,
            assetName: assetName,
            parentClassLabel: parentClassLabel,
            tuningItems: tuningItems,
            edgeItems: edgeItems,
            fontMicro: fontMicro,
            fontBody: fontBody,
            weightRegular: weightRegular,
            textPrimary: textPrimary,
          )
        : null;

    final bool hasLeftContent =
        doWidget != null || guardWidget != null || checkFooter != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useTwoColumnSpread =
            constraints.maxWidth >= 740 && rightVisual != null && hasLeftContent;

        if (!useTwoColumnSpread) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (doWidget != null) doWidget,
              if (guardWidget != null) ...[
                if (doWidget != null) const SizedBox(height: 8),
                guardWidget,
              ],
              if (rightVisual != null) ...[
                if (doWidget != null || guardWidget != null)
                  const SizedBox(height: 10),
                rightVisual,
              ],
              if (checkFooter != null) ...[
                if (doWidget != null ||
                    guardWidget != null ||
                    rightVisual != null)
                  const SizedBox(height: 9),
                checkFooter,
              ],
            ],
          );
        }

        // Wide Workbook Spread (>= 740px): Left ~38% (DO + Guard + Check) | Right ~62% (Godot Panel)
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 38,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (doWidget != null) doWidget,
                  if (guardWidget != null) ...[
                    if (doWidget != null) const SizedBox(height: 8),
                    guardWidget,
                  ],
                  if (checkFooter != null) ...[
                    if (doWidget != null || guardWidget != null)
                      const SizedBox(height: 10),
                    checkFooter,
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 62,
              child: rightVisual,
            ),
          ],
        );
      },
    );
  }

  String _summarizeSubStepForCollapsedRow(
    TaskHowToSubStep subStep, {
    required List<String> rawTableLines,
  }) {
    if (rawTableLines.length >= 3) {
      final firstData = rawTableLines
          .skip(2)
          .first
          .split('|')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .toList();
      if (firstData.length >= 2) {
        return firstData.take(3).join(' · ');
      }
    }
    final formula = subStep.codeFormula.trim().split('\n').first.trim();
    if (formula.isNotEmpty) {
      final cleaned = formula.replaceAll('[', '').replaceAll(']', '');
      return cleaned.length > 68 ? '${cleaned.substring(0, 65)}...' : cleaned;
    }
    final instr = subStep.instruction.trim();
    if (instr.length > 68) return '${instr.substring(0, 65)}...';
    return instr;
  }

  Set<String> _extractHoverTokensFromDoText(String text) {
    const stopWords = <String>{
      'the',
      'and',
      'for',
      'into',
      'from',
      'with',
      'that',
      'this',
      'under',
      'then',
      'set',
      'add',
      'get',
      'wire',
      'open',
      'select',
      'click',
      'drag',
      'rename',
      'inspector',
      'dock',
      'scene',
      'script',
      'variables',
      'default',
      'export',
      'signal',
      'signals',
      'property',
      'false',
      'true',
      'float',
      'bool',
      'vector',
      'vector2',
      'vector3',
      'node',
    };
    final tokens = <String>{};
    for (final m in RegExp(r'\b[A-Za-z_][A-Za-z0-9_]{2,}\b').allMatches(text)) {
      final t = m.group(0)!.toLowerCase();
      if (!stopWords.contains(t)) tokens.add(t);
    }
    for (final m in RegExp(r'\b(?:[A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,2})\b')
        .allMatches(text)) {
      final phrase = m.group(0)!.trim().toLowerCase();
      if (!stopWords.contains(phrase)) tokens.add(phrase);
    }
    for (final m
        in RegExp(r'\b[XYZ]\s*=\s*(-?\d+(?:\.\d+)?)\b').allMatches(text)) {
      final numVal = m.group(1);
      if (numVal != null && numVal.isNotEmpty && numVal != '0') {
        tokens.add(numVal);
      }
    }
    return tokens;
  }

  Widget _buildVerticalDoList({
    required String nodeId,
    required int selectedTaskIdx,
    required int sIdx,
    required List<String> items,
    required List<String> tuningItems,
    required List<String> edgeItems,
    required double fontMicro,
    required double fontBody,
    required FontWeight weightRegular,
    required FontWeight weightBold,
  }) {
    return Container(
      key: ValueKey('step_do_instruction_${nodeId}_${selectedTaskIdx}_$sIdx'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F18),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF1A2436)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              'DO',
              style: GoogleFonts.jetBrainsMono(
                fontSize: fontMicro,
                fontWeight: weightBold,
                letterSpacing: 0.7,
                color: const Color(0xFF38BDF8),
              ),
            ),
          ),
          for (int i = 0; i < items.length; i++)
            Builder(
              builder: (context) {
                final rowKey = '${nodeId}_${selectedTaskIdx}_${sIdx}_$i';
                final isRowHovered = _hoveredDoRowKey == rowKey;
                return MouseRegion(
                  key: ValueKey('step_do_item_hover_$rowKey'),
                  onEnter: (_) {
                    final tokens = _extractHoverTokensFromDoText(items[i]);
                    if (tokens.isEmpty) return;
                    _rebuild(() {
                      _hoveredDoRowKey = rowKey;
                      _hoveredDoTokens = tokens;
                    });
                  },
                  onExit: (_) {
                    if (_hoveredDoRowKey == rowKey) {
                      _rebuild(() {
                        _hoveredDoRowKey = null;
                        _hoveredDoTokens = const {};
                      });
                    }
                  },
                  child: Container(
                    margin:
                        EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isRowHovered
                          ? const Color(0xFF0EA5E9).withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: isRowHovered
                            ? const Color(0xFF38BDF8).withValues(alpha: 0.4)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          margin: const EdgeInsets.only(top: 1.5, right: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isRowHovered
                                ? const Color(0xFF0284C7)
                                : const Color(0xFF0E243D),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFF38BDF8)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: weightBold,
                              color: isRowHovered
                                  ? Colors.white
                                  : const Color(0xFF7DD3FC),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text.rich(
                            _buildSemanticStepSpan(
                              text: items[i],
                              baseStyle: GoogleFonts.inter(
                                fontSize: fontBody,
                                fontWeight: weightRegular,
                                height: 1.45,
                                color: const Color(0xFFCBD5E1),
                              ),
                              tuningItems: tuningItems,
                              edgeItems: edgeItems,
                              isCodeBlock: false,
                            ),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStepCheckFooter({
    required String nodeId,
    required int selectedTaskIdx,
    required int sIdx,
    required TaskHowToSubStep subStep,
    required String stepVerifyText,
    required List<String> tuningItems,
    required List<String> edgeItems,
    required double fontMicro,
    required FontWeight weightRegular,
    required FontWeight weightBold,
  }) {
    return Container(
      key: ValueKey('step_check_footer_${nodeId}_${selectedTaskIdx}_$sIdx'),
      padding: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF141D2E)),
        ),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: subStep.isEditorCheck
                  ? '↳ Editor Check: '
                  : '↳ Playtest Check: ',
              style: GoogleFonts.jetBrainsMono(
                fontSize: fontMicro,
                fontWeight: weightBold,
                color: subStep.isEditorCheck
                    ? const Color(0xFF38BDF8)
                    : const Color(0xFF34D399),
              ),
            ),
            _buildSemanticStepSpan(
              text: stepVerifyText,
              baseStyle: GoogleFonts.inter(
                fontSize: fontMicro,
                fontWeight: weightRegular,
                height: 1.4,
                color: const Color(0xFF94A3B8),
              ),
              tuningItems: tuningItems,
              edgeItems: edgeItems,
              isCodeBlock: false,
            ),
          ],
        ),
        softWrap: true,
      ),
    );
  }

  Widget? _buildStepRightVisualPane({
    required bool isDark,
    required List<String> effectiveTableLines,
    required String stepRawCode,
    required List<String> stepCodeLines,
    required String stepPathBadgeText,
    required ({String icon, String label, Color accent}) windowCtx,
    required String assetName,
    required String parentClassLabel,
    required List<String> tuningItems,
    required List<String> edgeItems,
    required double fontMicro,
    required double fontBody,
    required FontWeight weightRegular,
    required Color textPrimary,
  }) {
    if (effectiveTableLines.length >= 2) {
      return _buildLevelPlacementTable(
        effectiveTableLines,
        isDark: isDark,
        stepPath: stepPathBadgeText,
        assetName: assetName,
        parentClassLabel: parentClassLabel,
        isLevelScene: windowCtx.label == 'MAIN SCENE (.tscn)',
        isInputMap: windowCtx.label == 'INPUT MAP',
      );
    }
    if (stepCodeLines.isNotEmpty) {
      return _buildStepCodeLinesPane(
        stepCodeLines: stepCodeLines,
        stepPathBadgeText: stepPathBadgeText,
        windowCtx: windowCtx,
        tuningItems: tuningItems,
        edgeItems: edgeItems,
        fontMicro: fontMicro,
        fontBody: fontBody,
        weightRegular: weightRegular,
        textPrimary: textPrimary,
      );
    }
    return null;
  }

  Widget _buildStepCodeLinesPane({
    required List<String> stepCodeLines,
    required String stepPathBadgeText,
    required ({String icon, String label, Color accent}) windowCtx,
    required List<String> tuningItems,
    required List<String> edgeItems,
    required double fontMicro,
    required double fontBody,
    required FontWeight weightRegular,
    required Color textPrimary,
  }) {
    final signalLines =
        stepCodeLines.where((l) => l.contains('──►')).toList();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF06090F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1F2B3E)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF0D1422),
              border: Border(bottom: BorderSide(color: Color(0xFF1F2B3E))),
            ),
            child: Row(
              children: [
                Text(
                  '${windowCtx.icon} ${windowCtx.label}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: windowCtx.accent,
                  ),
                ),
                if (stepPathBadgeText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stepPathBadgeText,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (signalLines.isNotEmpty)
            Container(
              key: const ValueKey('godot_signal_flow_strip'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF08121E),
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFF22D3EE).withValues(alpha: 0.22),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final sigLine in signalLines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (int p = 0;
                              p <
                                  sigLine
                                      .split(RegExp(r'\s*(?:[└├]──►|──►)\s*'))
                                      .length;
                              p++) ...[
                            if (p > 0)
                              const Text(
                                '──►',
                                style: TextStyle(
                                  fontFamily: 'JetBrainsMono',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF22D3EE),
                                ),
                              ),
                            Builder(
                              builder: (context) {
                                final rawSeg = sigLine
                                    .split(RegExp(r'\s*(?:[└├]──►|──►)\s*'))[p]
                                    .trim();
                                final isSource = p == 0;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSource
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFF062E24),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: isSource
                                          ? const Color(0xFF38BDF8)
                                              .withValues(alpha: 0.45)
                                          : const Color(0xFF34D399)
                                              .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Text(
                                    rawSeg,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: fontMicro,
                                      fontWeight: FontWeight.w600,
                                      color: isSource
                                          ? const Color(0xFF7DD3FC)
                                          : const Color(0xFF6EE7B7),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int lineIdx = 0; lineIdx < stepCodeLines.length; lineIdx++)
                  Builder(
                    builder: (context) {
                      final rawCodeLine = stepCodeLines[lineIdx];
                      final isAddedDiffLine = rawCodeLine.startsWith('+') &&
                          !rawCodeLine.startsWith('++');
                      final normalizedLine = isAddedDiffLine
                          ? (rawCodeLine.startsWith('+ ')
                              ? rawCodeLine.substring(2)
                              : rawCodeLine.substring(1))
                          : rawCodeLine;
                      final prefixMatch = RegExp(
                        r'^(\s*(?:[└├]──►\s+|──►\s+|•\s+)?)',
                      ).firstMatch(normalizedLine);
                      final leadingPrefix = prefixMatch?.group(1) ?? '';
                      final bodyCodeLine = leadingPrefix.isNotEmpty &&
                              leadingPrefix.length < normalizedLine.length
                          ? normalizedLine.substring(leadingPrefix.length)
                          : normalizedLine;
                      final effectivePrefix = leadingPrefix.isNotEmpty &&
                              leadingPrefix.length < normalizedLine.length
                          ? leadingPrefix
                          : '';
                      return Container(
                        margin: EdgeInsets.only(
                          bottom: lineIdx == stepCodeLines.length - 1 ? 0 : 4,
                        ),
                        padding: isAddedDiffLine
                            ? const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              )
                            : EdgeInsets.zero,
                        decoration: isAddedDiffLine
                            ? BoxDecoration(
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.12),
                                border: const Border(
                                  left: BorderSide(
                                    color: Color(0xFF22C55E),
                                    width: 2.5,
                                  ),
                                ),
                              )
                            : null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 32,
                              child: Text(
                                isAddedDiffLine
                                    ? '+${(lineIdx + 1).toString().padLeft(2, '0')}'
                                    : (lineIdx + 1)
                                        .toString()
                                        .padLeft(2, '0'),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: fontMicro,
                                  fontWeight: isAddedDiffLine
                                      ? FontWeight.w700
                                      : weightRegular,
                                  height: 1.75,
                                  color: isAddedDiffLine
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ),
                            if (effectivePrefix.isNotEmpty)
                              Text(
                                effectivePrefix,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: fontBody,
                                  fontWeight: weightRegular,
                                  height: 1.75,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            Expanded(
                              child: Text.rich(
                                _buildSemanticStepSpan(
                                  text: bodyCodeLine,
                                  baseStyle: GoogleFonts.jetBrainsMono(
                                    fontSize: fontBody,
                                    fontWeight: weightRegular,
                                    height: 1.75,
                                    color: textPrimary,
                                  ),
                                  tuningItems: tuningItems,
                                  edgeItems: edgeItems,
                                  isCodeBlock: true,
                                ),
                                softWrap: true,
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
  }

  /// Splits single-line or bulleted `DO` text into numbered vertical micro-actions.
  List<String> _parseDoActionItems(String rawDo) {
    final trimmed = rawDo.trim();
    if (trimmed.isEmpty) return const [];
    final rawLines = trimmed
        .split('\n')
        .map(
          (l) => l
              .trim()
              .replaceFirst(
                RegExp(r'^(?:DO:\s*|[-*•]\s+|\d+[.)]\s+)'),
                '',
              )
              .trim(),
        )
        .where((l) => l.isNotEmpty)
        .toList();
    if (rawLines.length >= 2) return rawLines;

    final single = rawLines.isNotEmpty ? rawLines.first : trimmed;
    final semiParts = single
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.length >= 5)
        .toList();
    if (semiParts.length >= 2) return semiParts;

    final sentenceParts = single
        .split(RegExp(r'\.\s+(?=[A-Z])'))
        .map((s) => s.trim())
        .where((s) => s.length >= 5)
        .toList();
    if (sentenceParts.length >= 2) return sentenceParts;

    final actionSplit = single.split(
      RegExp(
        r',?\s+and\s+(?=(?:enable|set|assign|attach|drag|wire|connect|add|open|select|configure|create|rename|move|compile|save|check|verify)\b)',
        caseSensitive: false,
      ),
    );
    if (actionSplit.length >= 2) {
      return actionSplit.map((part) {
        final p = part.trim();
        if (p.isEmpty) return p;
        return p[0].toUpperCase() + p.substring(1);
      }).where((s) => s.isNotEmpty).toList();
    }
    return [single];
  }

  bool _hasRuntimeGraphNodes(String rawCode) {
    return RegExp(
      r'\b(?:_ready|_physics_process|_process|_input|_unhandled_input|body_entered|area_entered|timeout|pressed|button_down|animation_finished|move_and_slide|queue_free|is_on_floor|is_action_pressed|is_action_just_pressed|get_vector|get_axis|emit|connect|await|instantiate|queue_free|push_warning|look_at)\b',
      caseSensitive: false,
    ).hasMatch(rawCode);
  }

  /// Safety guard for `editor_setup` or passive Inspector setup steps that were
  /// serialized as `[Node] ──► [Set Prop (...)]` chains instead of a Markdown table.
  List<String> _tryConvertConfigGraphToTableLines(
    String rawCode, {
    required String stepDo,
    required String stepRole,
    required String defaultTarget,
  }) {
    final trimmed = rawCode.trim();
    if (!(trimmed.contains('──►') ||
        trimmed.contains('├──►') ||
        trimmed.contains('└──►'))) {
      return const [];
    }
    if (_hasRuntimeGraphNodes(trimmed)) return const [];

    final bool looksLikeSetupRole = stepRole == 'editor_setup';
    final bool looksLikeSetupDo = stepRole.isEmpty &&
        RegExp(
          r'^(?:configure|set|enable|disable|adjust|assign|attach|tweak|open)\b',
          caseSensitive: false,
        ).hasMatch(stepDo.trim()) &&
        !RegExp(
          r'\b(?:signal|connect|emit|when pressed|on overlap|on body entered)\b',
          caseSensitive: false,
        ).hasMatch(stepDo);

    if (!looksLikeSetupRole && !looksLikeSetupDo) return const [];

    final segments = trimmed
        .split(RegExp(r'\s*(?:[└├]──►|──►)\s*'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return const [];

    final tableRows = <String>[
      '| Node / Category | Property | Value |',
      '| --- | --- | --- |',
    ];
    String currentTarget =
        defaultTarget.trim().isNotEmpty ? defaultTarget.trim() : 'Root Node';

    for (final rawSeg in segments) {
      var seg = rawSeg;
      if (seg.startsWith('[')) seg = seg.substring(1);
      if (seg.endsWith(']')) seg = seg.substring(0, seg.length - 1);
      seg = seg.replaceAll(RegExp(r'\[\+\s*NEW\]', caseSensitive: false), '').trim();
      if (seg.isEmpty) continue;

      final parenIdx = seg.indexOf('(');
      final hasArgs = parenIdx > 0 && seg.endsWith(')');
      final baseName = hasArgs ? seg.substring(0, parenIdx).trim() : seg;
      final bool isSetter = RegExp(
        r'^(?:Set|Enable|Disable|Configure|Attach|Bind|Use)\s+',
        caseSensitive: false,
      ).hasMatch(baseName);

      if (!hasArgs && !isSetter) {
        currentTarget = baseName;
        continue;
      }

      var propName = baseName
          .replaceFirst(
            RegExp(r'^(?:Set|Configure)\s+', caseSensitive: false),
            '',
          )
          .trim();
      var valueText = 'true';
      if (hasArgs) {
        final rawArgs = seg.substring(parenIdx + 1, seg.length - 1).trim();
        final colonIdx = rawArgs.indexOf(':');
        if (colonIdx > 0 && !rawArgs.startsWith('X:')) {
          valueText = rawArgs.substring(colonIdx + 1).trim();
        } else {
          valueText = rawArgs;
        }
        final xyzMatch = RegExp(
          r'X\s*[:=]\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*Y\s*[:=]\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*Z\s*[:=]\s*(-?\d+(?:\.\d+)?)',
          caseSensitive: false,
        ).firstMatch(valueText);
        if (xyzMatch != null) {
          valueText =
              '(${xyzMatch.group(1)}, ${xyzMatch.group(2)}, ${xyzMatch.group(3)})';
        }
      }
      if (RegExp(r'^Enable\s+', caseSensitive: false).hasMatch(propName)) {
        propName = propName
            .replaceFirst(RegExp(r'^Enable\s+', caseSensitive: false), '')
            .trim();
        valueText = 'true';
      } else if (RegExp(r'^Disable\s+', caseSensitive: false).hasMatch(propName)) {
        propName = propName
            .replaceFirst(RegExp(r'^Disable\s+', caseSensitive: false), '')
            .trim();
        valueText = 'false';
      }
      tableRows.add('| $currentTarget | $propName | $valueText |');
    }

    return tableRows.length >= 3 ? tableRows : const [];
  }

  ({String icon, String label, Color accent}) _resolveWindowContextForSubStep(
    TaskHowToSubStep subStep, {
    required String activeTargetLabel,
  }) {
    final rawCode = subStep.codeFormula.trim();
    final lines = rawCode.isNotEmpty ? rawCode.split('\n') : const <String>[];
    final pipeLines = lines
        .where((l) => l.trim().startsWith('|') && l.trim().endsWith('|'))
        .toList();
    final hasSignalGraph = rawCode.contains('──►') ||
        rawCode.contains('└──►') ||
        rawCode.contains('├──►');
    final tableLines = pipeLines.length >= 2
        ? pipeLines
        : _tryConvertConfigGraphToTableLines(
            rawCode,
            stepDo: subStep.instruction.trim(),
            stepRole: subStep.stepRole ?? '',
            defaultTarget: activeTargetLabel,
          );
    final isEffectiveSignalGraph = hasSignalGraph && tableLines.isEmpty;
    return _resolveWindowContextBadge(
      stepPath: subStep.stepPath.trim(),
      instruction: subStep.instruction.trim(),
      codeFormula: rawCode,
      stepRole: subStep.stepRole ?? '',
      isRenderedAsInspectorTable: tableLines.length >= 2,
      isRenderedAsSignalGraph: isEffectiveSignalGraph,
    );
  }

  ({String icon, String label, Color accent}) _resolveWindowContextBadge({
    required String stepPath,
    required String instruction,
    required String codeFormula,
    String stepRole = '',
    bool isRenderedAsInspectorTable = false,
    bool isRenderedAsSignalGraph = false,
  }) {
    final lowerPath = stepPath.toLowerCase();
    final lowerInstr = instruction.toLowerCase();
    final lowerCode = codeFormula.toLowerCase();
    if (lowerPath.contains('project settings') ||
        lowerInstr.contains('project settings') ||
        lowerPath.contains('autoload') ||
        lowerInstr.contains('autoload')) {
      return (
        icon: '⚙',
        label: 'PROJECT SETTINGS',
        accent: const Color(0xFFF59E0B),
      );
    }
    if (!isRenderedAsSignalGraph &&
        (lowerPath.contains('input map') ||
            lowerInstr.contains('input map') ||
            lowerCode.contains('input map') ||
            (stepRole == 'editor_setup' &&
                (lowerInstr.contains('add action') ||
                    lowerInstr.contains('bind key') ||
                    lowerInstr.contains('inputmap'))))) {
      return (
        icon: '🎮',
        label: 'INPUT MAP',
        accent: const Color(0xFFA78BFA),
      );
    }
    final isPipeTable = codeFormula
            .split('\n')
            .where((l) => l.trim().startsWith('|') && l.trim().endsWith('|'))
            .length >=
        2;
    final bool isInspectorNodeSetup = lowerPath.contains('inspector') ||
        lowerPath.contains('scene dock') ||
        lowerCode.contains('collisionshape') ||
        lowerCode.contains('camera') ||
        lowerCode.contains('characterbody');
    if (lowerPath.contains('main scene') ||
        lowerPath.contains('level scene') ||
        lowerPath.contains('instantiate child scene') ||
        lowerInstr.contains('spawnpoint') ||
        lowerInstr.contains('instantiate child scene') ||
        (lowerPath.contains('scene tree') &&
            (lowerInstr.contains('instantiate') ||
                lowerInstr.contains('main'))) ||
        (isPipeTable && !isInspectorNodeSetup)) {
      return (
        icon: '🗺',
        label: 'MAIN SCENE (.tscn)',
        accent: const Color(0xFF10B981),
      );
    }
    final bool looksLikeCppFile = lowerPath.endsWith('.h') ||
        lowerPath.endsWith('.cpp') ||
        lowerCode.contains('gdclass(') ||
        lowerCode.contains('classdb::');
    final bool looksLikeGdScript = lowerPath.endsWith('.gd') ||
        lowerCode.contains('func ') ||
        lowerCode.contains('extends ') ||
        lowerCode.contains('@export');
    if (isRenderedAsInspectorTable ||
        (stepRole == 'editor_setup' && !looksLikeCppFile && !looksLikeGdScript) ||
        lowerPath.contains('inspector') ||
        lowerPath.contains('scene dock') ||
        lowerPath.contains('scene tree') ||
        lowerPath.contains('add child node')) {
      return (
        icon: '📐',
        label: 'SCENE TREE & INSPECTOR',
        accent: const Color(0xFF38BDF8),
      );
    }
    if (isRenderedAsSignalGraph ||
        lowerPath.contains('node dock') ||
        lowerPath.contains('signals') ||
        (lowerInstr.contains('connect') && lowerInstr.contains('signal'))) {
      return (
        icon: '⑂',
        label: 'NODE SIGNALS',
        accent: const Color(0xFF22D3EE),
      );
    }
    if (stepRole == 'wire_and_verify' &&
        (lowerInstr.contains('f6') ||
            lowerInstr.contains('f5') ||
            lowerInstr.contains('run scene') ||
            lowerPath.contains('run scene'))) {
      return (
        icon: '▶',
        label: 'RUN SCENE (F6)',
        accent: const Color(0xFF34D399),
      );
    }
    if (looksLikeCppFile) {
      return (
        icon: '⚡',
        label: 'GDEXTENSION C++',
        accent: const Color(0xFFA78BFA),
      );
    }
    return (
      icon: '📜',
      label: 'GDSCRIPT (.gd)',
      accent: const Color(0xFF38BDF8),
    );
  }

  Widget _buildLevelPlacementTable(
    List<String> lines, {
    required bool isDark,
    String stepPath = '',
    String assetName = '',
    String parentClassLabel = '',
    bool isLevelScene = false,
    bool isInputMap = false,
  }) {
    return GodotInspectorPanel(
      tableLines: lines,
      isDark: isDark,
      stepPath: stepPath,
      assetName: assetName,
      parentClassLabel: parentClassLabel,
      isLevelScene: isLevelScene,
      isInputMap: isInputMap,
      highlightedTokens: _hoveredDoTokens,
    );
  }
}
