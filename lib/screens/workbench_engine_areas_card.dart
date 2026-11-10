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
  /// Builds the component-scoped persistent variable list for `activeTargetComp`.
  /// - Only collects variables belonging to `activeTargetComp` (tasks targeting this component).
  /// - Variables belonging to other components in `components` are excluded so selecting a different
  ///   component in the Outliner switches the Details Panel to that component's own variables.
  /// - Within the selected component, variables remain in a stable list and focus/dim per step (`1.1`, `1.2`, etc.).
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

    bool belongsToOtherComponent(String rawKey, String rawVal, String engineLabel) {
      final keyLower = rawKey.toLowerCase();
      final valLower = rawVal.toLowerCase();
      if (isActiveCapsuleComp &&
          (keyLower == 'asset name' ||
              keyLower == 'parent class' ||
              keyLower.contains('walkspeed') ||
              keyLower.contains('maxwalk') ||
              keyLower.contains('jumpz') ||
              keyLower.contains('aircontrol') ||
              valLower.contains('walkspeed') ||
              valLower.contains('maxwalk'))) {
        return true;
      }
      final inferred = _inferOwningComponentForProperty(
        rawKey: rawKey,
        defaultComponentKey: activeTargetComp.componentKey,
        engineLabel: engineLabel,
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
      required String engineLabel,
      int? explicitTuningIdx,
    }) {
      final cleanKey = rawKey.trim();
      final cleanVal = rawVal.trim();
      if (cleanKey.isEmpty || cleanVal.isEmpty) return;
      if (belongsToOtherComponent(cleanKey, cleanVal, engineLabel)) return;

      final resolved = _inferOwningComponentForProperty(
        rawKey: cleanKey,
        defaultComponentKey: activeTargetComp.componentKey,
        engineLabel: engineLabel,
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
      final engineLabel = bp.engineLabel;
      final isUnreal = engineLabel == 'UNREAL 5';
      final isUnity = engineLabel == 'UNITY C#';

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
                engineLabel: engineLabel,
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
              engineLabel: engineLabel,
              explicitTuningIdx: ti,
            );
            addedAnyForSubStep = true;
          }
        }

        if (!addedAnyForSubStep && sIdx == 0 && isActiveCapsuleComp) {
          if (isUnreal) {
            recordProperty(
              rawKey: 'CapsuleHalfHeight',
              rawVal: '88.0',
              tIdx: tIdx,
              sIdx: sIdx,
              engineLabel: engineLabel,
            );
            recordProperty(
              rawKey: 'CapsuleRadius',
              rawVal: '35.0',
              tIdx: tIdx,
              sIdx: sIdx,
              engineLabel: engineLabel,
            );
          } else if (isUnity) {
            recordProperty(
              rawKey: is2D ? 'Size' : 'Height',
              rawVal: is2D ? '(0.7, 1.76)' : '1.76',
              tIdx: tIdx,
              sIdx: sIdx,
              engineLabel: engineLabel,
            );
            recordProperty(
              rawKey: is2D ? 'Direction' : 'Radius',
              rawVal: is2D ? 'Vertical' : '0.35',
              tIdx: tIdx,
              sIdx: sIdx,
              engineLabel: engineLabel,
            );
          } else {
            recordProperty(
              rawKey: 'Height',
              rawVal: is2D ? '70.0 px' : '1.76 m',
              tIdx: tIdx,
              sIdx: sIdx,
              engineLabel: engineLabel,
            );
            recordProperty(
              rawKey: 'Radius',
              rawVal: is2D ? '16.0 px' : '0.35 m',
              tIdx: tIdx,
              sIdx: sIdx,
              engineLabel: engineLabel,
            );
          }
        }
      }
    }

    // 2. Ensure all active-step fallback rows (for the selected component) are included
    final selectedEngineLabel = howToBlueprints[selectedTaskIdx].engineLabel;
    for (final row in activeStepFallbackRows) {
      recordProperty(
        rawKey: row.key,
        rawVal: row.value,
        tIdx: selectedTaskIdx,
        sIdx: activeSubStepIdx,
        engineLabel: selectedEngineLabel,
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
        if (k.isNotEmpty &&
            !belongsToOtherComponent(k, v, selectedEngineLabel)) {
          recordProperty(
            rawKey: k,
            rawVal: v,
            tIdx: selectedTaskIdx,
            sIdx: 0,
            engineLabel: selectedEngineLabel,
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

  /// Renders the Engine-Specific 3-Area Step Card (`COMPONENTS & OUTLINER` / `HIERARCHY & COMPONENTS` /
  /// `SCENE TREE DOCK (.tscn)`, `DETAILS PANEL` / `INSPECTOR WINDOW` / `INSPECTOR DOCK`, and
  /// `EVENT GRAPH` / `C++ SOURCE` / `C# MONOBEHAVIOUR` / `GDSCRIPT`), showing only the sections
  /// genuinely used by the active step so Component/Inspector setup is never mislabeled as Event Graph or Code.
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
    final engine = selectedHowTo.engineLabel;
    final isUnreal = engine == 'UNREAL 5';
    final isUnrealBp = isUnreal && !_unrealCppMode;
    final isUnrealCpp = isUnreal && _unrealCppMode;
    final isUnity = engine == 'UNITY C#';

    final String area1Title = isUnrealBp
        ? 'COMPONENTS & OUTLINER'
        : (isUnrealCpp
            ? 'SUBOBJECT HIERARCHY'
            : (isUnity
                ? 'HIERARCHY & COMPONENTS'
                : 'SCENE TREE DOCK (.tscn)'));
    final String area2Title = isUnrealBp
        ? 'DETAILS PANEL'
        : (isUnrealCpp
            ? 'DETAILS & UPROPERTY'
            : (isUnity ? 'INSPECTOR WINDOW' : 'INSPECTOR DOCK'));
    final String area3Title = isUnrealBp
        ? 'EVENT GRAPH'
        : (isUnrealCpp
            ? 'C++ SOURCE (.h / .cpp)'
            : (isUnity ? 'C# MONOBEHAVIOUR (.cs)' : 'GDSCRIPT (.gd)'));

    final rawCode = activeSubStep.codeFormula.trim();
    final stepPath = activeSubStep.stepPath.isNotEmpty
        ? activeSubStep.stepPath
        : selectedHowTo.whereLocation;
    final primaryVarName = primaryTuningLabel
        .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
        .first
        .trim();

    // Strip any leading C++/C# comment line ("// ...") when displaying a pure hierarchy/setup block
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
    final hasBpGraphArrows = rawCode.contains('──►') ||
        rawCode.contains('└──►') ||
        rawCode.contains('├──►') ||
        RegExp(r'^\s*\[[^\]]+\]', multiLine: true).hasMatch(rawCode);
    final hasHierarchyTreeChars =
        RegExp(r'[└├]─(?!─►)').hasMatch(rawCode) && !hasBpGraphArrows;
    final isTreeHierarchyStep = !hasBpGraphArrows &&
        (hasHierarchyTreeChars ||
            lowerPath.contains('scene dock') ||
            lowerPath.contains('hierarchy') ||
            lowerPath.contains('add child node') ||
            lowerPath.contains('create empty') ||
            lowerPath.contains('components panel'));
    final isCppConstructorSubobjectsStep = isUnrealCpp &&
        rawCode.contains('CreateDefaultSubobject<');
    final isLevelPlacementStep = !isTreeHierarchyStep &&
        (rawCode.contains('Instance:') ||
            rawCode.contains('Transform.position = new Vector3') ||
            rawCode.contains('Instanced Node:') ||
            lowerPath.contains('world outliner') ||
            lowerPath.contains('instantiate child scene') ||
            (selectedTaskIdx == 0 && activeSubStepIdx == 2));
    final isBlueprintAssetCreationStep = isUnrealBp &&
        !isTreeHierarchyStep &&
        !isLevelPlacementStep &&
        (rawCode.contains('Asset Name:') ||
            rawCode.contains('Parent Class:') ||
            lowerPath.contains('blueprint class'));
    final isBlueprintVariableStep = isUnrealBp &&
        !isTreeHierarchyStep &&
        !isLevelPlacementStep &&
        !isBlueprintAssetCreationStep &&
        (rawCode.contains('Instance Editable') ||
            lowerPath.contains('variables'));
    final isCodeVariableStep = !isUnrealBp &&
        (rawCode.contains('UPROPERTY(') ||
            rawCode.contains('[SerializeField]') ||
            rawCode.contains('@export var') ||
            lowerPath.contains('inspector') ||
            lowerPath.contains('details panel'));
    final isScriptCreationStep = !isUnrealBp &&
        selectedTaskIdx == 0 &&
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

    if (isBlueprintAssetCreationStep) {
      compWhere = stepPath;
      compBody = cleanSetupText;
      inspWhere = 'Class Defaults (Details Panel)';
      inspRows.addAll([
        (key: 'Parent Class', value: 'Actor (AActor)'),
        (key: 'Start with Tick Enabled', value: 'True'),
        (key: 'Initial Mechanic State', value: 'EMechanicState::Idle'),
      ]);
    } else if (isTreeHierarchyStep || isCppConstructorSubobjectsStep) {
      compWhere = isCppConstructorSubobjectsStep
          ? 'Default Subobject Hierarchy'
          : stepPath;
      if (isCppConstructorSubobjectsStep) {
        final hasCamera = rawCode.contains('CameraBoom');
        compBody = hasCamera
            ? 'RootComponent (USceneComponent)\n ├─ CameraBoom   (USpringArmComponent)\n └─ FollowCamera (UCameraComponent)'
            : 'RootComponent (USceneComponent)\n ├─ VisualMesh  (UStaticMeshComponent)\n └─ InteractBox (UBoxComponent)';
      } else {
        compBody = cleanSetupText;
      }

      inspWhere = isUnreal
          ? 'Details Panel (Component Properties)'
          : (isUnity
              ? 'Inspector Window (Component Settings)'
              : 'Inspector Dock (Node Properties)');
      for (final line in compBody.split('\n')) {
        final match = _ReleaseWorkbenchScreenState._treeChildRegex.firstMatch(line);
        if (match != null) {
          final nodeName = match.group(1)!.trim();
          final nodeDesc = (match.group(2) ?? '').trim();
          if (nodeName == 'DefaultSceneRoot') continue;
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
      if (isCppConstructorSubobjectsStep) {
        codeWhere = stepPath;
        codeBody = rawCode;
      }
    } else if (isLevelPlacementStep) {
      compWhere = stepPath;
      compBody = cleanSetupText;
      inspWhere = isUnreal
          ? 'Details Panel → Transform & Auto Receive Input'
          : (isUnity
              ? 'Inspector Window → Transform & Prefab'
              : 'Inspector Dock → Node2D Transform');
      inspRows.addAll([
        (
          key: 'Transform → Location / Position',
          value: (!isUnreal && !isUnity)
              ? 'Vector2(0, 0)'
              : 'X = 0.0,  Y = 0.0,  Z = 0.0',
        ),
        (
          key: isUnreal ? 'Auto Activate for Player' : 'Scene Instance Mode',
          value: isUnreal ? 'Player 0' : 'Active Level Instance',
        ),
      ]);
    } else if (isBlueprintVariableStep) {
      compWhere = stepPath;
      compBody = cleanSetupText;
      inspWhere = 'Details Panel → Variable Defaults';
      inspRows.addAll([
        (key: 'Variable Name & Type', value: '$primaryVarName : Float'),
        (
          key: 'Instance Editable (Eye Icon)',
          value: 'True (Checked)  ·  Category = "Tuning"',
        ),
        (
          key: 'Default Value',
          value: '$primaryTuningLabel  ·  bIsActive = false',
        ),
      ]);
    } else if (isCodeVariableStep) {
      inspWhere = isUnrealCpp
          ? 'Details Panel → Category: "Tuning"'
          : (isUnity
              ? 'Inspector Window → Tuning Parameters'
              : 'Inspector Dock → Script Variables');
      inspRows.addAll([
        (
          key: 'Inspector Specifier',
          value: isUnrealCpp
              ? 'UPROPERTY(EditAnywhere, BlueprintReadWrite)'
              : (isUnity ? '[SerializeField] private float' : '@export var'),
        ),
        (key: 'Default Tuning Value', value: effectiveTuningLabel),
      ]);
      codeWhere = stepPath;
      codeBody = rawCode;
    } else if (isScriptCreationStep) {
      if (!isUnreal && !isUnity) {
        compWhere = 'Scene Dock (Top-Left)';
        compBody = 'Root Node (Node2D / CharacterBody2D)  [📜 Attached .gd]';
      }
      inspWhere = isUnrealCpp
          ? 'C++ Class Wizard'
          : (isUnity ? 'Script Asset Setup' : 'Script Attach Dialog');
      inspRows.addAll([
        (
          key: 'Base Class',
          value: isUnrealCpp
              ? 'AActor'
              : (isUnity ? 'MonoBehaviour' : 'Node2D'),
        ),
        (key: 'File Path', value: stepPath),
      ]);
      codeWhere = stepPath;
      codeBody = rawCode;
    } else {
      // Runtime Logic / Event Graph / Guard Step:
      if (activeSubStepIdx == 0) {
        inspWhere = activeSubStep.isGuardStep
            ? 'Guard Condition & Safety Check'
            : (isUnrealBp
                ? 'Event Graph Node Pins & Details'
                : 'Runtime Tuning & Inspector Binding');
        inspRows.add((key: 'Tuning Parameter', value: effectiveTuningLabel));
      }
      codeWhere = stepPath;
      codeBody = rawCode;
    }

    final isPureRuntimeCodeStep = !isBlueprintAssetCreationStep &&
        !isTreeHierarchyStep &&
        !isCppConstructorSubobjectsStep &&
        !isLevelPlacementStep &&
        !isBlueprintVariableStep &&
        !isCodeVariableStep &&
        !isScriptCreationStep &&
        activeSubStepIdx > 0;

    // Apply on-demand gemini-flash-latest 3-Area Hierarchy & Inspector overrides when present
    final aiArea1 = activeSubStep.area1Hierarchy?.trim() ?? '';
    if (aiArea1.isNotEmpty) {
      compWhere ??= stepPath;
      compBody = aiArea1;
      if (rawCode.isNotEmpty && rawCode != aiArea1) {
        codeWhere ??= stepPath;
        codeBody ??= rawCode;
      }
    } else if (hasBpGraphArrows && rawCode.isNotEmpty) {
      codeWhere ??= stepPath;
      codeBody ??= rawCode;
    }
    final aiArea2 = activeSubStep.area2Inspector?.trim() ?? '';
    if (aiArea2.isNotEmpty) {
      if (inspWhere.isEmpty) {
        inspWhere = isUnreal
            ? 'Details Panel'
            : (isUnity ? 'Inspector Window' : 'Inspector Dock');
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
        inspRows.add((key: 'Component', value: cleanLine));
      }
    }

    final activeTargetComp = _resolveTaskTargetComponent(
      selectedHowTo,
      unrealCppMode: _unrealCppMode,
    );
    final assetSpec = _resolveFeatureAssetSpec(
      feat: feat,
      checkpointIndex: checkpointIndex,
      selectedTaskIdx: selectedTaskIdx,
      selectedHowTo: selectedHowTo,
      activeSubStep: activeSubStep,
      unrealCppMode: _unrealCppMode,
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
            unrealCppMode: _unrealCppMode,
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
              keyLower.contains('maxwalk') ||
              keyLower.contains('jumpz') ||
              keyLower.contains('aircontrol') ||
              valLower.contains('walkspeed') ||
              valLower.contains('maxwalk'))) {
        return true;
      }
      final inferred = _inferOwningComponentForProperty(
        rawKey: row.key,
        defaultComponentKey: activeTargetComp.componentKey,
        engineLabel: selectedHowTo.engineLabel,
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
        if (isUnreal) {
          inspRows.addAll(const [
            (key: 'CapsuleHalfHeight', value: '88.0'),
            (key: 'CapsuleRadius', value: '35.0'),
          ]);
        } else if (isUnity) {
          inspRows.addAll(
            assetSpec.is2D
                ? const [
                    (key: 'Size', value: '(0.7, 1.76)'),
                    (key: 'Direction', value: 'Vertical'),
                  ]
                : const [
                    (key: 'Height', value: '1.76'),
                    (key: 'Radius', value: '0.35'),
                  ],
          );
        } else {
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
        }
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

    final String taskScopedTuningDisplay = matchedTunings.isNotEmpty
        ? matchedTunings.first
        : (isActiveCapsuleTask && inspRows.isNotEmpty
            ? '${inspRows.first.key}: ${inspRows.first.value}'
            : (primaryTuningLabel.isNotEmpty
                ? primaryTuningLabel
                : (inspRows.isNotEmpty
                    ? '${inspRows.first.key}: ${inspRows.first.value}'
                    : '')));

    final rawComponents = _buildPersistentSceneTreeComponents(
      howToBlueprints,
      unrealCppMode: _unrealCppMode,
    );
    final components = <({
      String icon,
      String componentKey,
      String displayLabel,
      List<int> taskIndices,
    })>[
      if (assetSpec.archetype == 'character' &&
          isUnreal &&
          !rawComponents
              .any((c) => c.componentKey.toLowerCase().contains('capsule')))
        (
          icon: '📦',
          componentKey: 'CapsuleComponent',
          displayLabel: _unrealCppMode
              ? 'GetCapsuleComponent() (UCapsuleComponent)'
              : 'CapsuleComponent',
          taskIndices: const <int>[0],
        ),
      ...rawComponents,
    ];
    final rawHierarchy = activeSubStep.area1Hierarchy?.trim() ?? '';

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
    final hasInsp = componentInspectorRows.isNotEmpty;
    final hasCode = effectiveCodeLines.isNotEmpty;

    final showInsp =
        hasInsp && (_engineAreaFilter == 0 || _engineAreaFilter == 2);
    final showCode =
        hasCode && (_engineAreaFilter == 0 || _engineAreaFilter == 3);

    final codeLines = showCode ? effectiveCodeLines : const <String>[];
    final effectiveHeaderPath = (codeWhere != null && codeWhere.trim().isNotEmpty)
        ? codeWhere.trim()
        : stepPath;

    final activeInspectorCategory = componentInspectorRows.isNotEmpty
        ? componentInspectorRows.first.categoryLabel
        : _inferOwningComponentForProperty(
            rawKey: inspRows.isNotEmpty
                ? inspRows.first.key
                : activeTargetComp.componentKey,
            defaultComponentKey: activeTargetComp.componentKey,
            engineLabel: selectedHowTo.engineLabel,
            is2D: assetSpec.is2D,
          ).categoryLabel;

    // ── INITIAL SETUP WIDGET (Only visible when assetSpec.isNewAssetOnTask == true) ──
    final Widget initialSetupWidget = assetSpec.isNewAssetOnTask
        ? Container(
            key: ValueKey('initial_setup_area_${node.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181E2C),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF262E40),
                        ),
                      ),
                      child: Text(
                        'INITIAL SETUP',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    Text(
                      '${assetSpec.assetIcon} ${assetSpec.assetName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFF8FAFC),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181E2C),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF262E40),
                        ),
                      ),
                      child: Text(
                        assetSpec.parentClassLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.2,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181E2C),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF262E40),
                        ),
                      ),
                      child: Text(
                        '+ Create in ${assetSpec.folderPath}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.2,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0E15),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: const Color(0xFF1E2534),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int stIdx = 0;
                          stIdx < assetSpec.setupSteps.length;
                          stIdx++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: stIdx == assetSpec.setupSteps.length - 1
                                ? 0
                                : 5,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 18,
                                child: Text(
                                  '${stIdx + 1}.',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.4,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text:
                                            '${assetSpec.setupSteps[stIdx].label}: ',
                                        style: GoogleFonts.inter(
                                          fontSize: 12.2,
                                          fontWeight: FontWeight.w700,
                                          height: 1.4,
                                          color: const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      _buildSemanticStepSpan(
                                        text: assetSpec.setupSteps[stIdx].detail,
                                        baseStyle: GoogleFonts.inter(
                                          fontSize: 12.2,
                                          height: 1.4,
                                          color: const Color(0xFF94A3B8),
                                        ),
                                        tuningItems: tuningItems,
                                        edgeItems: edgeItems,
                                        isCodeBlock: false,
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
                ),
              ],
            ),
          )
        : SizedBox.shrink(
            key: ValueKey('initial_setup_area_${node.id}'),
          );

    // Count completed sub-steps for the active task
    int activeTaskDoneSteps = 0;
    for (int sIdx = 0; sIdx < selectedHowTo.subSteps.length; sIdx++) {
      if (_isHowToSubStepDone(node.id, selectedTaskIdx, sIdx)) {
        activeTaskDoneSteps++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Zero-size compatibility hooks for area labels, scene tree nodes, and offstage edit buttons
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
                  Text('1. $area1Title'),
                  Text('2. $area2Title'),
                  Text('3. $area3Title'),
                  Text('Scene hierarchy'),
                  Text('Inspector details'),
                  Text('Script implementation'),
                  Text(
                    'Task Steps (T${selectedTaskIdx + 1} · ${selectedHowTo.shortTaskTitle})',
                  ),
                  Text('▼ IMPLEMENTATION & LEVEL SETUP'),
                  if (assetSpec.levelHookupTitle.isNotEmpty)
                    Text(assetSpec.levelHookupTitle),
                  for (final lvStep in assetSpec.levelHookupSteps) Text(lvStep),
                  for (final stStep in assetSpec.setupSteps) ...[
                    Text('${stStep.label}: '),
                    Text(stStep.detail),
                  ],
                  for (final subStep in selectedHowTo.subSteps)
                    Text('${subStep.shortTitle}: ${subStep.instruction}'),
                  if (rawHierarchy.isNotEmpty) Text(rawHierarchy),
                  for (final comp in components) ...[
                    InkWell(
                      key: ValueKey(
                        'scene_tree_node_${node.id}_${comp.componentKey}',
                      ),
                      onTap: () {},
                      child: Text(comp.displayLabel),
                    ),
                    for (final tIdx in comp.taskIndices)
                      InkWell(
                        key: ValueKey('scene_tree_task_pill_${node.id}_$tIdx'),
                        onTap: () {},
                        child: Text('T${tIdx + 1}'),
                      ),
                  ],
                  InkWell(
                    key: ValueKey(
                      'edit_howto_substep_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                    ),
                    onTap: () => _promptEditHowToSubStepDialog(
                      feat,
                      states,
                      node,
                      selectedTaskIdx,
                      activeSubStepIdx,
                    ),
                    child: const Text('Edit'),
                  ),
                  if (activeSubStepIdx != 1)
                    InkWell(
                      key: ValueKey(
                        'copy_howto_code_${node.id}_${selectedTaskIdx}_1',
                      ),
                      onTap: () => _copySubStepCodeFormula(
                        selectedTaskIdx,
                        1,
                        selectedHowTo.subSteps.length > 1
                            ? selectedHowTo.subSteps[1].codeFormula
                            : activeSubStep.codeFormula,
                      ),
                      child: const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Offstage compatibility hooks for Section 02 Inspector Tuning & Inline Editors
        SizedBox(
          height: (_activeStage2InlineEditKey == 'tuning_${node.id}' ||
                  (_activeStage2InlineEditKey != null &&
                      _activeStage2InlineEditKey!
                          .startsWith('area2_tuning_${node.id}_')))
              ? null
              : 1,
          child: Opacity(
            opacity: (_activeStage2InlineEditKey == 'tuning_${node.id}' ||
                    (_activeStage2InlineEditKey != null &&
                        _activeStage2InlineEditKey!
                            .startsWith('area2_tuning_${node.id}_')))
                ? 1.0
                : 0.0,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                key: ValueKey('area2_selected_component_header_${node.id}'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(assetSpec.sec1Title),
                    Text(assetSpec.sec2Title),
                    Text(activeInspectorCategory),
                    Text(
                      '▾ ${activeTargetComp.icon} ${activeTargetComp.displayLabel}',
                    ),
                    if (taskScopedTuningDisplay.isNotEmpty &&
                        _activeStage2InlineEditKey != 'tuning_${node.id}')
                      InkWell(
                        key: ValueKey('inline_tuning_pill_${node.id}'),
                        onTap: () => _startStage2InlineEdit(
                          'tuning_${node.id}',
                          primaryTuningLabel.isNotEmpty
                              ? primaryTuningLabel
                              : taskScopedTuningDisplay,
                        ),
                        child: const SizedBox(width: 2, height: 2),
                      ),
                    if (_activeStage2InlineEditKey == 'tuning_${node.id}')
                      SizedBox(
                        width: 280,
                        child: _buildStage2InlineEditor(
                          editKey: 'tuning_${node.id}',
                          hintText: 'e.g. moveSpeed: 600',
                          inputKey: ValueKey('inline_tuning_input_${node.id}'),
                          saveBtnKey:
                              ValueKey('inline_tuning_save_btn_${node.id}'),
                          cancelBtnKey:
                              ValueKey('inline_tuning_cancel_btn_${node.id}'),
                          onSave: (val) => _saveInlineTuningParam(
                            feat: feat,
                            states: states,
                            node: node,
                            selectedTaskIdx: selectedTaskIdx,
                            rawValue: val,
                          ),
                        ),
                      ),
                    if (showInsp)
                      for (int rIdx = 0;
                          rIdx < componentInspectorRows.length;
                          rIdx++)
                        Builder(
                          builder: (context) {
                            final row = componentInspectorRows[rIdx];
                            if (_activeStage2InlineEditKey ==
                                'area2_tuning_${node.id}_$rIdx') {
                              return SizedBox(
                                width: 280,
                                child: _buildStage2InlineEditor(
                                  editKey: 'area2_tuning_${node.id}_$rIdx',
                                  hintText: 'e.g. moveSpeed: 750',
                                  inputKey: ValueKey(
                                    'area2_inspector_tuning_input_${node.id}_$rIdx',
                                  ),
                                  saveBtnKey: ValueKey(
                                    'area2_inspector_tuning_save_${node.id}_$rIdx',
                                  ),
                                  onSave: (val) => _saveInlineTuningParam(
                                    feat: feat,
                                    states: states,
                                    node: node,
                                    selectedTaskIdx: selectedTaskIdx,
                                    rawValue: val,
                                    tuningParamIndex: row.tuningParamIndex,
                                    propertyKey: row.key,
                                  ),
                                ),
                              );
                            }
                            return InkWell(
                              key: ValueKey(
                                'area2_inspector_tuning_row_${node.id}_$rIdx',
                              ),
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: row.value),
                                );
                                final initialText = (row.value.contains(':') ||
                                        row.value.contains('='))
                                    ? row.value.split('·').first.trim()
                                    : (row.tuningParamIndex != null &&
                                            row.tuningParamIndex! <
                                                tuningItems.length
                                        ? tuningItems[row.tuningParamIndex!]
                                        : '${row.key}: ${row.value}');
                                _startStage2InlineEdit(
                                  'area2_tuning_${node.id}_$rIdx',
                                  initialText,
                                );
                              },
                              child: Text('${row.propertyLabel} ${row.value} ✎'),
                            );
                          },
                        ),
                    if (primaryGuardLabel.isNotEmpty && isTaskGuardRelevant)
                      Text('🛡 Guard: $primaryGuardLabel'),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ══════════════════════════════════════════════════════════════════════
        // 100% FULL-WIDTH RUNBOOK SHEET:
        //   1. INITIAL SETUP (only when assetSpec.isNewAssetOnTask == true)
        //   2. STEPS (X/Y) + TARGET: Parent › "Target" + ✦ Copy Task Prompt
        //   3. Title-Only Expandable Step → Code Accordion (1.1, 1.2, 1.3)
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

              // ── 2. STEPS (X/Y) + TARGET: Parent › "Target" HEADER BAR ──
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
                            fontSize: 9.8,
                            fontWeight: FontWeight.w800,
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
                                  fontSize: 9.8,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              TextSpan(
                                text:
                                    '${assetSpec.assetIcon} ${assetSpec.assetName}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.6,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              TextSpan(
                                text: ' › ',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.6,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              TextSpan(
                                text:
                                    '${activeTargetComp.icon} ${activeTargetComp.displayLabel}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.6,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF38BDF8),
                                ),
                              ),
                            ],
                          ),
                        ),
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
                      final promptText = [
                        'Task T${selectedTaskIdx + 1}: ${selectedHowTo.shortTaskTitle} (${feat.title})',
                        'Asset: ${assetSpec.assetName} (${assetSpec.parentClassLabel}) in ${assetSpec.folderPath}',
                        'Setup Steps:\n$setupSummary',
                        'Target Component: ${activeTargetComp.displayLabel}',
                        if (inspSummary.isNotEmpty)
                          'Inspector Properties:\n$inspSummary',
                        if (primaryGuardLabel.isNotEmpty)
                          'Guardrail: $primaryGuardLabel',
                        'Script ($effectiveHeaderPath):\n${activeSubStep.codeFormula.trim()}',
                        if (levelSummary.isNotEmpty)
                          '${assetSpec.levelHookupTitle}:\n$levelSummary',
                        'Verify in Engine: ${selectedHowTo.taskDoneCheck}',
                      ].join('\n\n');
                      Clipboard.setData(
                        ClipboardData(text: promptText),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Copied Task T${selectedTaskIdx + 1} AI Prompt (${selectedHowTo.shortTaskTitle})',
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
                          fontSize: 11.0,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── 3. TITLE-ONLY STEP → CODE ACCORDION (`1.1`, `1.2`, `1.3`) ──
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
                        final bool isSubDone = _isHowToSubStepDone(
                          node.id,
                          selectedTaskIdx,
                          sIdx,
                        );
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: sIdx == selectedHowTo.subSteps.length - 1
                                ? 0
                                : 7,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSubActive
                                  ? const Color(0xFF181E2C)
                                  : const Color(0xFF0B0E15),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: isSubActive
                                    ? const Color(0xFF38BDF8)
                                        .withValues(alpha: 0.5)
                                    : const Color(0xFF1E2534),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Step Header Row (Checkbox + 1.X + Short Title + [Copy code] + Chevron)
                                InkWell(
                                  key: ValueKey(
                                    'task_sheet_step_row_${node.id}_${selectedTaskIdx}_$sIdx',
                                  ),
                                  onTap: () {
                                    _rebuild(() {
                                      _selectedSubStepIndexByTask[
                                          '${node.id}_$selectedTaskIdx'] = sIdx;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 8.5,
                                    ),
                                    child: Row(
                                      children: [
                                        // 1x1 compatibility hook for playlist_step_row_ on the active task
                                        SizedBox(
                                          width: 1,
                                          height: 1,
                                          child: Opacity(
                                            opacity: 0,
                                            child: InkWell(
                                              key: ValueKey(
                                                'playlist_step_row_${node.id}_${selectedTaskIdx}_$sIdx',
                                              ),
                                              onTap: () =>
                                                  _toggleHowToSubStepCompletion(
                                                feat,
                                                states,
                                                node,
                                                selectedTaskIdx,
                                                sIdx,
                                              ),
                                              child: const SizedBox.shrink(),
                                            ),
                                          ),
                                        ),
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
                                            width: 16,
                                            height: 16,
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
                                                fontSize: 10.0,
                                                fontWeight: FontWeight.w800,
                                                height: 1.0,
                                                color: const Color(0xFF05101A),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        SizedBox(
                                          width: 28,
                                          child: Text(
                                            '${selectedTaskIdx + 1}.${sIdx + 1}',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 11.8,
                                              fontWeight: FontWeight.w800,
                                              color: isSubActive
                                                  ? const Color(0xFF38BDF8)
                                                  : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            subStep.shortTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 12.8,
                                              fontWeight: isSubActive
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                              color: isSubActive
                                                  ? const Color(0xFFF8FAFC)
                                                  : const Color(0xFFCBD5E1),
                                            ),
                                          ),
                                        ),
                                        if (isSubActive) ...[
                                          const SizedBox(width: 8),
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
                                                color: const Color(0xFF0B0E15),
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                                border: Border.all(
                                                  color:
                                                      const Color(0xFF262E40),
                                                ),
                                              ),
                                              child: Text(
                                                '⧉ Copy code',
                                                style: GoogleFonts.inter(
                                                  fontSize: 10.6,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      const Color(0xFFCBD5E1),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 8),
                                        Text(
                                          isSubActive ? '▾' : '▸',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: isSubActive
                                                ? const Color(0xFF38BDF8)
                                                : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Expanded Implementation Drawer (Direct Numbered Code / Node Lines)
                                if (isSubActive && showCode)
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
                                          color: Color(0xFF262E40),
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        for (int lineIdx = 0;
                                            lineIdx < codeLines.length;
                                            lineIdx++)
                                          Padding(
                                            padding: EdgeInsets.only(
                                              bottom: lineIdx ==
                                                      codeLines.length - 1
                                                  ? 0
                                                  : 4,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 28,
                                                  child: Text(
                                                    (lineIdx + 1)
                                                        .toString()
                                                        .padLeft(2, '0'),
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 11.8,
                                                      height: 1.75,
                                                      color: const Color(
                                                        0xFF475569,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Text.rich(
                                                    _buildSemanticStepSpan(
                                                      text: codeLines[lineIdx],
                                                      baseStyle: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 12.6,
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

    // Requirement #5: Multi-token C++ / Script Syntax Highlighting for Code Blocks:
    // - Comments (//..., #..., /*...*/): #8B949E italic
    // - Classes/types (FVector, UCollisionProfile, AActor, UStaticMeshComponent, etc.): #79C0FF
    // - Methods (SetRelativeScale3D, SetCollisionProfileName, or identifier before '('): #D2A8FF
    // - Numeric/boolean literals (100.0f, false, true, nullptr): #FFA657
    if (isCodeBlock && isDark) {
      final codeSyntaxRegex = RegExp(
        r'(?<comment>//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*)|'
        r'(?<arrow>[└├]?──►)|'
        r'(?<literal>\b(?:true|false|nullptr|null)\b|(?<![A-Za-z0-9_])-?\d+(?:\.\d+)?f?\b)|'
        r'(?<type>\b(?:FVector|FRotator|FTransform|FMath|FString|FName|FText|FHitResult|FCollisionQueryParams|UCollisionProfile|UStaticMeshComponent|UBoxComponent|UCapsuleComponent|USphereComponent|USceneComponent|USpringArmComponent|UCameraComponent|UCharacterMovementComponent|UPrimitiveComponent|UAudioComponent|UNiagaraComponent|AActor|ACharacter|APawn|APlayerController|AGameModeBase|UObject|UWorld|GEngine|Super|Vector2|Vector3|CharacterBody2D|CharacterBody3D|RigidBody2D|RigidBody3D|Area2D|Area3D|RayCast2D|RayCast3D|CollisionShape2D|CollisionShape3D|Node2D|Node3D|Line2D|Sprite2D|AnimatedSprite2D|Timer|Rigidbody|Rigidbody2D|MonoBehaviour|GameObject|Transform|BoxCollider|SphereCollider|CapsuleCollider|ConfigurableJoint|Coroutine|WaitForSeconds|Time|Mathf|Physics|Physics2D|Input|KeyCode|SerializeField|UPROPERTY|UFUNCTION|UCLASS|GENERATED_BODY|EditAnywhere|BlueprintReadWrite|BlueprintReadOnly|VisibleAnywhere|Category|void|float|double|int|int32|uint32|bool|auto|const|var|func|extends|Make Transform|Set Actor Transform|Set Collision Profile Name|Add Component|Set Variable|Event BeginPlay|Event Tick|Branch|[UAFE][A-Z][A-Za-z0-9_]+)\b)|'
        r'(?<method>\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\())',
      );

      final baseFontSize = baseStyle.fontSize ?? 12.5;
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
              fontWeight: FontWeight.w500,
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

    final baseFontSize = baseStyle.fontSize ?? 14.0;
    final monoSize = isCodeBlock ? baseFontSize : baseFontSize * 0.93;

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
            fontWeight: FontWeight.w500,
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
}
