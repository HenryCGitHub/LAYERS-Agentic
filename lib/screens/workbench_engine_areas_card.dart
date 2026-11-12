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

    final effectiveCardUnrealCpp =
        _unrealCppMode && _classifyFeatureArchetype(feat.title) != 'level';
    final activeTargetComp = _resolveTaskTargetComponent(
      selectedHowTo,
      unrealCppMode: effectiveCardUnrealCpp,
    );
    final assetSpec = _resolveFeatureAssetSpec(
      feat: feat,
      checkpointIndex: checkpointIndex,
      selectedTaskIdx: selectedTaskIdx,
      selectedHowTo: selectedHowTo,
      activeSubStep: activeSubStep,
      unrealCppMode: effectiveCardUnrealCpp,
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
            unrealCppMode: effectiveCardUnrealCpp,
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
      unrealCppMode: effectiveCardUnrealCpp,
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
                        key: ValueKey(
                          'scene_tree_task_pill_${node.id}_${comp.componentKey}_$tIdx',
                        ),
                        onTap: () {},
                        child: Text('T${tIdx + 1}'),
                      ),
                  ],
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
                        child: const SizedBox(width: 8, height: 2),
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
                    Text(assetSpec.sec1Title),
                    Text(assetSpec.sec2Title),
                    Text(activeInspectorCategory),
                    Text(
                      '▾ ${activeTargetComp.icon} ${activeTargetComp.displayLabel}',
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
                      if (selectedHowTo.subSteps.length > 1)
                        Builder(
                          builder: (context) {
                            final allCollapsed = List<int>.generate(
                              selectedHowTo.subSteps.length,
                              (i) => i,
                            ).every(
                              (i) => _collapsedSubStepKeys.contains(
                                '${node.id}_${selectedTaskIdx}_$i',
                              ),
                            );
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
                                    if (allCollapsed) {
                                      _collapsedSubStepKeys.remove(k);
                                    } else {
                                      _collapsedSubStepKeys.add(k);
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
                                  allCollapsed ? 'Expand all' : 'Collapse all',
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
                        final bool isStepExpanded =
                            !_collapsedSubStepKeys.contains(stepCollapseKey);
                        final String stepRawCode = subStep.codeFormula.trim();
                        final bool isStepBpGraph =
                            stepRawCode.contains('──►') ||
                                stepRawCode.contains('└──►') ||
                                stepRawCode.contains('├──►');
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
                        final bool isEffectiveBpGraph =
                            isStepBpGraph && effectiveTableLines.isEmpty;
                        final windowCtx = _resolveWindowContextForSubStep(
                          subStep,
                          isUnrealCpp: effectiveCardUnrealCpp,
                          activeTargetLabel: activeTargetComp.displayLabel,
                        );
                        final prevWindowCtx = sIdx > 0
                            ? _resolveWindowContextForSubStep(
                                selectedHowTo.subSteps[sIdx - 1],
                                isUnrealCpp: effectiveCardUnrealCpp,
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
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
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
                                              if (stepPathBadgeText
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
                                                _collapsedSubStepKeys
                                                    .add(stepCollapseKey);
                                              } else {
                                                _collapsedSubStepKeys
                                                    .remove(stepCollapseKey);
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
                                        // 0. Context-Switch Callout (only when moving to a different UE5 Editor window)
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
                                              '↳ Switch to ${windowCtx.icon} ${windowCtx.label}',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: windowCtx.accent,
                                              ),
                                            ),
                                          ),
                                        // 1-4. Responsive 2-Column Workbook Spread (Left: DO + Guard + Check | Right: UE5 Panel)
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
                                          isEffectiveBpGraph:
                                              isEffectiveBpGraph,
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
    required bool isEffectiveBpGraph,
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
            isEffectiveBpGraph: isEffectiveBpGraph,
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

        // Wide Workbook Spread (>= 740px): Left ~38% (DO + Guard + Check) | Right ~62% (UE5 Panel)
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
            Padding(
              padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(top: 1.5, right: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E243D),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: weightBold,
                        color: const Color(0xFF7DD3FC),
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
    required bool isEffectiveBpGraph,
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
    if (isEffectiveBpGraph && stepRawCode.isNotEmpty) {
      final parsedGraph = UeBlueprintGraphCanvas.parseFromFormula(stepRawCode);
      if (parsedGraph.nodes.isEmpty) return null;
      return UeBlueprintGraphCanvas(
        nodes: parsedGraph.nodes,
        wires: parsedGraph.wires,
      );
    }
    if (effectiveTableLines.length >= 2) {
      return _buildLevelPlacementTable(
        effectiveTableLines,
        isDark: isDark,
        stepPath: stepPathBadgeText,
        assetName: assetName,
        parentClassLabel: parentClassLabel,
        isLevelOutliner: windowCtx.label == 'LEVEL EDITOR',
        isInputMapping: windowCtx.label == 'INPUT MAPPING',
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
                          ? rawCodeLine.substring(1)
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
      r'\b(?:event|beginplay|tick|ia_|enhancedinput|inputaction|branch|delay|timer|timeline|oncomponent|onactor|spawnactor|destroy|apply\s*damage|take\s*damage|overlap|hit|pressed|released|triggered|print|cast\s+to|get\s+player|line\s*trace|sphere\s*trace|custom\s*event|return|for\s*each|foreach|switch\s+on|flip\s*flop|do\s+once|gate|sequence|add\s+movement|add\s+controller|launch\s*character|play\s*montage|play\s*sound|set\s*timer|bind)\b',
      caseSensitive: false,
    ).hasMatch(rawCode);
  }

  /// Safety guard for `editor_setup` or passive component setup steps that were
  /// serialized as `[Comp] ──► [Set Prop (...)]` chains instead of a Markdown table.
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
          r'\b(?:wire|graph|event|on press|when pressed|on overlap|on hit)\b',
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
      '| Component / Actor | Property | Value |',
      '| --- | --- | --- |',
    ];
    String currentTarget =
        defaultTarget.trim().isNotEmpty ? defaultTarget.trim() : 'Actor Defaults';

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
    required bool isUnrealCpp,
    required String activeTargetLabel,
  }) {
    final rawCode = subStep.codeFormula.trim();
    final lines = rawCode.isNotEmpty ? rawCode.split('\n') : const <String>[];
    final pipeLines = lines
        .where((l) => l.trim().startsWith('|') && l.trim().endsWith('|'))
        .toList();
    final isBpGraph = rawCode.contains('──►') ||
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
    final isEffectiveGraph = isBpGraph && tableLines.isEmpty;
    return _resolveWindowContextBadge(
      stepPath: subStep.stepPath.trim(),
      instruction: subStep.instruction.trim(),
      codeFormula: rawCode,
      isUnrealCpp: isUnrealCpp,
      stepRole: subStep.stepRole ?? '',
      isRenderedAsDetailsTable: tableLines.length >= 2,
      isRenderedAsBpGraph: isEffectiveGraph,
    );
  }

  ({String icon, String label, Color accent}) _resolveWindowContextBadge({
    required String stepPath,
    required String instruction,
    required String codeFormula,
    required bool isUnrealCpp,
    String stepRole = '',
    bool isRenderedAsDetailsTable = false,
    bool isRenderedAsBpGraph = false,
  }) {
    final lowerPath = stepPath.toLowerCase();
    final lowerInstr = instruction.toLowerCase();
    final lowerCode = codeFormula.toLowerCase();
    if (lowerPath.contains('world settings') ||
        lowerInstr.contains('world settings') ||
        lowerInstr.contains('gamemode override')) {
      return (
        icon: '⚙',
        label: 'WORLD SETTINGS',
        accent: const Color(0xFFF59E0B),
      );
    }
    final isPipeTable = codeFormula
            .split('\n')
            .where((l) => l.trim().startsWith('|') && l.trim().endsWith('|'))
            .length >=
        2;
    final bool isBpOrDetailsSetup = lowerPath.contains('bp_') ||
        lowerPath.contains('components') ||
        lowerPath.contains('details') ||
        lowerPath.contains('imc_') ||
        lowerPath.contains('input mapping') ||
        lowerCode.contains('firstperson') ||
        lowerCode.contains('charmove') ||
        lowerCode.contains('capsule') ||
        lowerCode.contains('camera') ||
        lowerCode.contains('pawn control');
    if (lowerPath.contains('outliner') ||
        lowerPath.contains('level editor') ||
        lowerPath.contains('place actors') ||
        lowerInstr.contains('playerstart') ||
        (lowerPath.contains('viewport') &&
            !lowerPath.contains('bp_') &&
            !lowerPath.contains('blueprint') &&
            !lowerPath.contains('components') &&
            !lowerPath.contains('details')) ||
        (isPipeTable && !isBpOrDetailsSetup)) {
      return (
        icon: '🌍',
        label: 'LEVEL EDITOR',
        accent: const Color(0xFF10B981),
      );
    }
    if (!isRenderedAsBpGraph &&
        (lowerPath.contains('imc_') ||
            lowerPath.contains('input mapping') ||
            (stepRole == 'editor_setup' &&
                (lowerInstr.contains('imc_') ||
                    lowerInstr.contains('ia_') ||
                    lowerInstr.contains('mapping context'))))) {
      return (
        icon: '🎮',
        label: 'INPUT MAPPING',
        accent: const Color(0xFFA78BFA),
      );
    }
    final bool looksLikeCppFile = lowerPath.endsWith('.h') ||
        lowerPath.endsWith('.cpp') ||
        lowerCode.contains('uproperty') ||
        lowerCode.contains('createdefaultsubobject');
    if (isRenderedAsDetailsTable ||
        (stepRole == 'editor_setup' && !looksLikeCppFile) ||
        lowerPath.contains('details') ||
        lowerPath.contains('components')) {
      return (
        icon: '📐',
        label: 'DETAILS PANEL',
        accent: const Color(0xFF38BDF8),
      );
    }
    if (isUnrealCpp ||
        lowerPath.contains('.h') ||
        lowerPath.contains('.cpp') ||
        lowerCode.contains('uproperty') ||
        lowerCode.contains('createdefaultsubobject') ||
        lowerCode.contains('->')) {
      return (
        icon: '📜',
        label: 'C++ (.h / .cpp)',
        accent: const Color(0xFFA78BFA),
      );
    }
    if (isRenderedAsBpGraph) {
      return (
        icon: '⑂',
        label: 'EVENT GRAPH',
        accent: const Color(0xFF38BDF8),
      );
    }
    return (
      icon: '📘',
      label: 'BLUEPRINT EDITOR',
      accent: const Color(0xFF38BDF8),
    );
  }

  Widget _buildLevelPlacementTable(
    List<String> lines, {
    required bool isDark,
    String stepPath = '',
    String assetName = '',
    String parentClassLabel = '',
    bool isLevelOutliner = false,
    bool isInputMapping = false,
  }) {
    return UeDetailsInspectorPanel(
      tableLines: lines,
      isDark: isDark,
      stepPath: stepPath,
      assetName: assetName,
      parentClassLabel: parentClassLabel,
      isLevelOutliner: isLevelOutliner,
      isInputMapping: isInputMapping,
    );
  }
}
