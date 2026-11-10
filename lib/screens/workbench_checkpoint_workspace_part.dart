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
    int? tuningParamIndex,
    String? propertyKey,
  }) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final tuningItems = node.tuningParams;
    int targetIdx =
        tuningItems.isNotEmpty ? (selectedTaskIdx % tuningItems.length) : 0;
    if (tuningParamIndex != null &&
        tuningParamIndex >= 0 &&
        tuningParamIndex < tuningItems.length) {
      targetIdx = tuningParamIndex;
    } else if (tuningItems.isNotEmpty) {
      final candidateKey = (propertyKey ?? trimmed)
          .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
          .first
          .trim()
          .toLowerCase();
      final matchedIdx = tuningItems.indexWhere(
        (tp) =>
            tp
                .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
                .first
                .trim()
                .toLowerCase() ==
            candidateKey,
      );
      if (matchedIdx != -1) {
        targetIdx = matchedIdx;
      }
    }
    final oldEntry = tuningItems.isNotEmpty ? tuningItems[targetIdx] : '';
    final oldVar = oldEntry
        .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
        .first
        .trim();
    final newVar = trimmed
        .split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex)
        .first
        .trim();

    if (propertyKey != null && propertyKey.isNotEmpty) {
      final parts = trimmed.split(
        _ReleaseWorkbenchScreenState._tuningVarDelimiterRegex,
      );
      final valOnly = parts.length > 1
          ? parts.sublist(1).join(':').trim()
          : trimmed;
      _customComponentPropertyOverrides['${node.id}::$propertyKey'] = valOnly;
    }

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

  /// Resolves a concrete engine component noun (never a verb phrase) for a `[T]` Task.
  ({String icon, String componentKey, String displayLabel})
      _resolveTaskTargetComponent(
    TaskHowToBlueprint bp, {
    required bool unrealCppMode,
  }) {
    final isUnreal = bp.engineLabel.contains('UNREAL');
    final isUnity = bp.engineLabel.contains('UNITY');
    final verbPrefixRegex = RegExp(
      r'^(?:add|trace|calculate|clamp|trigger|respawn|set|bind|configure|create|implement|update|apply|check|verify|enforce|spawn|handle|process|execute|run)\b',
      caseSensitive: false,
    );

    final draft = widget.workbench.conceptDraft;
    final specCombined = [
      ...(draft?.gameSpec ?? const <String>[]),
      ...(draft?.techSpec ?? const <String>[]),
      draft?.goal ?? '',
    ].join(' ').toLowerCase();
    final is2D = specCombined.contains('2d') ||
        specCombined.contains('pixel') ||
        specCombined.contains('sprite') ||
        specCombined.contains('side-scroller');

    // 0. Check task title first so Capsule / Collider foundation tasks never fall through to child Movement components
    final titleLower = bp.shortTaskTitle.toLowerCase();
    if (titleLower.contains('capsule') ||
        titleLower.contains('collider') ||
        titleLower.contains('collision hull') ||
        titleLower.contains('collision shape')) {
      if (isUnreal) {
        return (
          icon: '📦',
          componentKey: 'CapsuleComponent',
          displayLabel: unrealCppMode
              ? 'CapsuleComponent (UCapsuleComponent)'
              : 'CapsuleComponent (CollisionCylinder)',
        );
      } else if (isUnity) {
        return (
          icon: '📦',
          componentKey: is2D ? 'CapsuleCollider2D' : 'CharacterController',
          displayLabel: is2D
              ? 'CapsuleCollider2D (2D Physics)'
              : 'CharacterController (Capsule Collider)',
        );
      } else {
        return (
          icon: '📦',
          componentKey: is2D ? 'CollisionShape2D' : 'CollisionShape3D',
          displayLabel: is2D
              ? 'CollisionShape2D (CapsuleShape2D)'
              : 'CollisionShape3D (CapsuleShape3D)',
        );
      }
    }

    // 0b. Check task title for Arena / Floor / Ramp / Blockout geometry so it never falls through to IMC_Default or CharacterMovement
    if (titleLower.contains('floor') ||
        titleLower.contains('arena') ||
        titleLower.contains('geometry') ||
        titleLower.contains('blockout') ||
        titleLower.contains('slab') ||
        titleLower.contains('platform')) {
      if (isUnreal) {
        return (
          icon: '📦',
          componentKey: 'StaticMeshActor_ArenaFloor',
          displayLabel: unrealCppMode
              ? 'ArenaFloorMesh (UStaticMeshComponent)'
              : 'StaticMeshActor_ArenaFloor (StaticMesh)',
        );
      } else if (isUnity) {
        return (
          icon: '📦',
          componentKey: 'ArenaFloor',
          displayLabel: is2D
              ? 'ArenaFloor (BoxCollider2D)'
              : 'ArenaFloor (MeshCollider / BoxCollider)',
        );
      } else {
        return (
          icon: '📦',
          componentKey: 'ArenaFloor',
          displayLabel: is2D
              ? 'ArenaFloor (StaticBody2D)'
              : 'ArenaFloor (StaticBody3D)',
        );
      }
    }
    if (titleLower.contains('ramp') || titleLower.contains('incline')) {
      if (isUnreal) {
        return (
          icon: '🦴',
          componentKey: 'StaticMeshActor_Ramp_Incline',
          displayLabel: unrealCppMode
              ? 'RampInclineMesh (UStaticMeshComponent)'
              : 'StaticMeshActor_Ramp_Incline (StaticMesh)',
        );
      } else if (isUnity) {
        return (
          icon: '🦴',
          componentKey: 'RampInclineMesh',
          displayLabel: 'RampInclineMesh (MeshCollider)',
        );
      } else {
        return (
          icon: '🦴',
          componentKey: 'RampInclineMesh',
          displayLabel: is2D
              ? 'RampInclineMesh (StaticBody2D)'
              : 'RampInclineMesh (StaticBody3D)',
        );
      }
    }

    // 1. Check if any subStep has an explicit area1Hierarchy child component noun (prioritizing ← SELECTED / [ACTIVE])
    final isInputTaskTitle =
        titleLower.contains('input') || titleLower.contains('mapping');
    for (final step in bp.subSteps) {
      final rawH = step.area1Hierarchy?.trim() ?? '';
      if (rawH.isNotEmpty) {
        final lines = rawH.split('\n');
        final orderedLines = <String>[
          ...lines.where(
            (l) => l.contains('← SELECTED') || l.contains('[ACTIVE]'),
          ),
          ...lines.reversed,
        ];
        for (final rawLine in orderedLines) {
          final clean = rawLine
              .replaceAll(RegExp(r'^[├└│─\s•\-🎯📦⚙️📷🦴🧩📁⚡]+'), '')
              .replaceAll('[ACTIVE]', '')
              .replaceAll('← SELECTED', '')
              .trim();
          if (clean.isEmpty ||
              clean.startsWith('[Root]') ||
              clean.toLowerCase().startsWith('class ')) {
            continue;
          }
          final cleanLower = clean.toLowerCase();
          if (!isInputTaskTitle &&
              (cleanLower.startsWith('imc_') ||
                  cleanLower.contains('input mapping context') ||
                  cleanLower.startsWith('ia_') ||
                  cleanLower.contains('input action'))) {
            continue;
          }
          if (!verbPrefixRegex.hasMatch(clean)) {
            final key = clean.split('(').first.trim();
            final lower = cleanLower;
            final icon = lower.contains('camera')
                ? '📷'
                : (lower.contains('box') ||
                        lower.contains('capsule') ||
                        lower.contains('trigger') ||
                        lower.contains('collision') ||
                        lower.contains('area') ||
                        lower.contains('ray') ||
                        lower.contains('floor') ||
                        lower.contains('volume')
                    ? '📦'
                    : (lower.contains('mesh') ||
                            lower.contains('sprite') ||
                            lower.contains('visual') ||
                            lower.contains('ramp')
                        ? '🦴'
                        : '⚙️'));
            return (
              icon: icon,
              componentKey: key.isNotEmpty ? key : clean,
              displayLabel: clean,
            );
          }
        }
      }
    }

    // 2. Classify by task title + goal + code formulas to map to canonical engine components
    final combinedText = [
      bp.shortTaskTitle,
      bp.taskGoalSentence,
      for (final s in bp.subSteps) '${s.shortTitle} ${s.codeFormula}',
    ].join(' ').toLowerCase();

    if (combinedText.contains('camera') ||
        combinedText.contains('fade') ||
        combinedText.contains('fov') ||
        combinedText.contains('springarm')) {
      if (isUnreal) {
        return (
          icon: '📷',
          componentKey: 'PlayerCameraManager',
          displayLabel: unrealCppMode
              ? 'PlayerCameraManager (APlayerCameraManager)'
              : 'PlayerCameraManager (CameraComp)',
        );
      } else if (isUnity) {
        return (
          icon: '📷',
          componentKey: 'MainCamera',
          displayLabel: 'MainCamera (Camera)',
        );
      } else {
        return (
          icon: '📷',
          componentKey: 'CameraNode',
          displayLabel: 'CameraNode (Camera2D/3D)',
        );
      }
    }

    if (combinedText.contains('collision') ||
        combinedText.contains('trigger') ||
        combinedText.contains('perimeter') ||
        combinedText.contains('overlap') ||
        combinedText.contains('raycast') ||
        combinedText.contains('line trace') ||
        combinedText.contains('hitbox') ||
        combinedText.contains('volume')) {
      if (isUnreal) {
        return (
          icon: '📦',
          componentKey: 'PerimeterFallTrigger',
          displayLabel: unrealCppMode
              ? 'PerimeterFallTrigger (UBoxComponent)'
              : 'PerimeterFallTrigger (BoxComponent)',
        );
      } else if (isUnity) {
        return (
          icon: '📦',
          componentKey: 'PerimeterTrigger',
          displayLabel: 'PerimeterTrigger (BoxCollider)',
        );
      } else {
        return (
          icon: '📦',
          componentKey: 'CollisionTrigger',
          displayLabel: 'CollisionTrigger (Area2D/3D)',
        );
      }
    }

    if (combinedText.contains('velocity') ||
        combinedText.contains('movement') ||
        combinedText.contains('teleport') ||
        combinedText.contains('clamp') ||
        combinedText.contains('respawn') ||
        combinedText.contains('boundary') ||
        combinedText.contains('planar') ||
        combinedText.contains('vector') ||
        combinedText.contains('fall') ||
        combinedText.contains('reset') ||
        combinedText.contains('dash') ||
        combinedText.contains('strafe') ||
        combinedText.contains('jump') ||
        combinedText.contains('impulse')) {
      if (isUnreal) {
        return (
          icon: '⚙️',
          componentKey: 'CharacterMovement',
          displayLabel: unrealCppMode
              ? 'CharacterMovement (UCharacterMovementComponent)'
              : 'CharacterMovement (MovementComp)',
        );
      } else if (isUnity) {
        return (
          icon: '⚙️',
          componentKey: 'CharacterMovement',
          displayLabel: 'CharacterMovement (Rigidbody)',
        );
      } else {
        return (
          icon: '⚙️',
          componentKey: 'CharacterMovement',
          displayLabel: 'CharacterMovement (CharacterBody)',
        );
      }
    }

    if (combinedText.contains('mesh') ||
        combinedText.contains('sprite') ||
        combinedText.contains('trail') ||
        combinedText.contains('vfx') ||
        combinedText.contains('niagara') ||
        combinedText.contains('hud') ||
        combinedText.contains('widget')) {
      if (isUnreal) {
        return (
          icon: '🦴',
          componentKey: 'CharacterMesh0',
          displayLabel: 'CharacterMesh0 (SkeletalMesh)',
        );
      } else if (isUnity) {
        return (
          icon: '🎨',
          componentKey: 'VisualRenderer',
          displayLabel: 'VisualRenderer (MeshRenderer)',
        );
      } else {
        return (
          icon: '🎨',
          componentKey: 'VisualNode',
          displayLabel: 'VisualNode (Sprite2D/Node)',
        );
      }
    }

    final derivedAsset = TaskHowToBlueprint.deriveConcreteAssetName(
      bp.shortTaskTitle,
    ).pascalName;
    final cleanKey =
        derivedAsset.isNotEmpty ? derivedAsset : 'GameplayComponent';
    return (
      icon: '⚙️',
      componentKey: cleanKey,
      displayLabel: isUnreal
          ? '$cleanKey (ActorComponent)'
          : (isUnity ? '$cleanKey (MonoBehaviour)' : '$cleanKey (Node)'),
    );
  }

  /// Resolves engine-native asset metadata, parent/root class, folder path, listed-out setup steps,
  /// and listed-out level/scene setup steps for Design C (Single Calm Card) across Unreal 5 BP, Unreal 5 C++, Unity C#, and Godot 4.
  ({
    String archetype,
    bool is2D,
    String sec1Title,
    String sec2Title,
    String sec3Title,
    String assetIcon,
    String assetName,
    String parentClassLabel,
    String folderPath,
    bool isNewAssetOnTask,
    List<({String label, String detail})> setupSteps,
    String levelHookupTitle,
    List<String> levelHookupSteps,
  }) _resolveFeatureAssetSpec({
    required TierDocument feat,
    required int checkpointIndex,
    required int selectedTaskIdx,
    required TaskHowToBlueprint selectedHowTo,
    required TaskHowToSubStep activeSubStep,
    required bool unrealCppMode,
    required ({String icon, String componentKey, String displayLabel})
        activeTargetComp,
  }) {
    final engineLabel = selectedHowTo.engineLabel;
    final isUnreal = engineLabel.contains('UNREAL');
    final isUnrealBp = isUnreal && !unrealCppMode;
    final isUnrealCpp = isUnreal && unrealCppMode;
    final isUnity = engineLabel.contains('UNITY');

    final draft = widget.workbench.conceptDraft;
    final specCombined = [
      ...(draft?.gameSpec ?? const <String>[]),
      ...(draft?.techSpec ?? const <String>[]),
      draft?.goal ?? '',
    ].join(' ').toLowerCase();
    final is2D = specCombined.contains('2d') ||
        specCombined.contains('pixel') ||
        specCombined.contains('sprite') ||
        specCombined.contains('side-scroller');

    final lowerTitle = feat.title.toLowerCase();
    final String archetype;
    if (RegExp(
      r'\b(?:hud|ui|widget|hotbar|menu|crosshair|selector|health\s*bar|inventory\s*bar|radar|minimap)\b',
    ).hasMatch(lowerTitle)) {
      archetype = 'ui';
    } else if (RegExp(
      r'\b(?:player|character|pawn|strafe|locomotion|dash|sprint|jump|crouch|slide|grapple|parry|aim|camera|footstep)\b',
    ).hasMatch(lowerTitle)) {
      archetype = 'character';
    } else if (RegExp(
      r'\b(?:arena|blockout|greybox|graybox|level|map|compound|sector|courtyard|room|world|stage|zone|biome|terrain)\b',
    ).hasMatch(lowerTitle)) {
      archetype = 'level';
    } else {
      archetype = 'actor';
    }

    final derivedNames = TaskHowToBlueprint.deriveConcreteAssetName(feat.title);
    final pascalName = derivedNames.pascalName.isNotEmpty
        ? derivedNames.pascalName
        : 'GameplayFeature';
    final snakeName = derivedNames.snakeName.isNotEmpty
        ? derivedNames.snakeName
        : 'gameplay_feature';

    // Check if an earlier feature in the release already created the shared Character asset
    final allReleaseFeats = <TierDocument>[
      for (final b in widget.workbench.activeReleaseBeats)
        ...widget.workbench.featuresForBeat(b.id),
    ];
    final featIdx = allReleaseFeats.indexWhere((f) => f.id == feat.id);
    bool isFirstOfArchetype = true;
    bool hasPrecedingCharacter = false;
    if (featIdx > 0) {
      for (int i = 0; i < featIdx; i++) {
        final prevLower = allReleaseFeats[i].title.toLowerCase();
        final isPrevChar = RegExp(
          r'\b(?:player|character|pawn|strafe|locomotion|dash|sprint|jump|crouch|slide|grapple|parry|aim|camera|footstep)\b',
        ).hasMatch(prevLower);
        if (isPrevChar) {
          hasPrecedingCharacter = true;
        }
        if (archetype == 'character' && isPrevChar) {
          isFirstOfArchetype = false;
        }
      }
    }
    final isNewAssetOnTask =
        selectedTaskIdx == 0 && checkpointIndex == 0 && isFirstOfArchetype;
    final verifyCheckLower = selectedHowTo.taskDoneCheck.toLowerCase();
    final needsPlayerSpawnSetup =
        (archetype == 'level' || archetype == 'actor') &&
            (!hasPrecedingCharacter ||
                verifyCheckLower.contains('player') ||
                verifyCheckLower.contains('character') ||
                verifyCheckLower.contains('pawn') ||
                verifyCheckLower.contains('land') ||
                verifyCheckLower.contains('stand') ||
                verifyCheckLower.contains('spawn'));

    final sec1Title = archetype == 'level'
        ? (isUnreal
            ? 'World Outliner & Level Actors'
            : (isUnity
                ? 'Scene Hierarchy & GameObjects'
                : 'Scene Tree & Level Nodes'))
        : (isUnrealBp
            ? 'Blueprint & Components'
            : (isUnrealCpp
                ? 'C++ Class & Subobjects (.h)'
                : (isUnity
                    ? 'Prefab & Components (Hierarchy)'
                    : 'Scene & Nodes (.tscn)')));
    final sec2Title = isUnrealBp || (isUnreal && archetype == 'level')
        ? 'Details Panel Values'
        : (isUnrealCpp
            ? 'UPROPERTY & Default Values'
            : (isUnity ? 'Inspector Window Values' : 'Inspector Dock Values'));
    final sec3Title = archetype == 'level'
        ? (isUnreal
            ? 'Level Blueprint & World Settings'
            : (isUnity
                ? 'Scene Setup & C# Behaviour'
                : 'Level Script (.gd) & World Setup'))
        : (isUnrealBp
            ? 'Event Graph & Level Setup'
            : (isUnrealCpp
                ? 'C++ Implementation (.cpp) & Level Setup'
                : (isUnity
                    ? 'C# MonoBehaviour (.cs) & Scene Setup'
                    : 'GDScript (.gd) & Main Scene Setup')));

    final assetIcon = archetype == 'level'
        ? '🗺'
        : (isUnrealBp
            ? '📘'
            : (isUnrealCpp ? '⚡' : (isUnity ? '📦' : '🎬')));

    String assetName;
    String parentClassLabel;
    String folderPath;
    if (archetype == 'character') {
      if (isUnrealBp) {
        assetName = 'BP_PlayerCharacter';
        parentClassLabel = 'Parent Class: Character (ACharacter)';
        folderPath = '/Game/Characters/';
      } else if (isUnrealCpp) {
        assetName = 'APlayerCharacter';
        parentClassLabel = 'Base Class: ACharacter';
        folderPath = 'Source/Characters/';
      } else if (isUnity) {
        assetName = 'PlayerCharacter.prefab';
        parentClassLabel = 'Root: GameObject + PlayerController.cs';
        folderPath = 'Assets/Prefabs/Characters/';
      } else {
        assetName = 'player_character.tscn';
        parentClassLabel =
            is2D ? 'Root Node: CharacterBody2D' : 'Root Node: CharacterBody3D';
        folderPath = 'res://scenes/characters/';
      }
    } else if (archetype == 'ui') {
      if (isUnrealBp) {
        assetName = 'WBP_$pascalName';
        parentClassLabel = 'Parent Class: UserWidget (UUserWidget)';
        folderPath = '/Game/UI/';
      } else if (isUnrealCpp) {
        assetName = 'U${pascalName}Widget';
        parentClassLabel = 'Base Class: UUserWidget';
        folderPath = 'Source/UI/';
      } else if (isUnity) {
        assetName = '${pascalName}Canvas.prefab';
        parentClassLabel = 'Root: Canvas + ${pascalName}UI.cs';
        folderPath = 'Assets/Prefabs/UI/';
      } else {
        assetName = '${snakeName}_hud.tscn';
        parentClassLabel = 'Root Node: Control (CanvasLayer)';
        folderPath = 'res://scenes/ui/';
      }
    } else if (archetype == 'level') {
      final cleanLevelPascal = pascalName.replaceAll(
        RegExp(r'(?:Blockout|Greybox|Graybox)$', caseSensitive: false),
        '',
      );
      final effectiveLevelPascal =
          cleanLevelPascal.isNotEmpty ? cleanLevelPascal : pascalName;
      final cleanLevelSnake = snakeName.replaceAll(
        RegExp(r'_(?:blockout|greybox|graybox)$', caseSensitive: false),
        '',
      );
      final effectiveLevelSnake =
          cleanLevelSnake.isNotEmpty ? cleanLevelSnake : snakeName;
      if (isUnreal) {
        assetName = 'L_$effectiveLevelPascal';
        parentClassLabel = 'Asset Type: Level Map (.umap)';
        folderPath = '/Game/Maps/';
      } else if (isUnity) {
        assetName = '$effectiveLevelPascal.unity';
        parentClassLabel = 'Asset Type: Scene (.unity)';
        folderPath = 'Assets/Scenes/';
      } else {
        assetName = '$effectiveLevelSnake.tscn';
        parentClassLabel = is2D
            ? 'Root Node: Node2D (Level Scene)'
            : 'Root Node: Node3D (Level Scene)';
        folderPath = 'res://scenes/levels/';
      }
    } else {
      if (isUnrealBp) {
        assetName = 'BP_$pascalName';
        parentClassLabel = 'Parent Class: Actor (AActor)';
        folderPath = '/Game/Gameplay/';
      } else if (isUnrealCpp) {
        assetName = 'A$pascalName';
        parentClassLabel = 'Base Class: AActor';
        folderPath = 'Source/Gameplay/';
      } else if (isUnity) {
        assetName = '$pascalName.prefab';
        parentClassLabel = 'Root: GameObject + ${pascalName}Controller.cs';
        folderPath = 'Assets/Prefabs/Gameplay/';
      } else {
        assetName = '$snakeName.tscn';
        parentClassLabel = is2D ? 'Root Node: Node2D' : 'Root Node: Node3D';
        folderPath = 'res://scenes/gameplay/';
      }
    }

    final setupSteps = <({String label, String detail})>[];
    if (isNewAssetOnTask) {
      if (archetype == 'character') {
        if (isUnrealBp) {
          setupSteps.addAll([
            (
              label: 'Asset',
              detail: 'Blueprint Class (Character) → $folderPath$assetName',
            ),
            (
              label: 'Root',
              detail: 'Select inherited CapsuleComponent (Root)',
            ),
            (
              label: 'Camera',
              detail: '+ Add → FirstPersonCamera under CapsuleComponent',
            ),
          ]);
        } else if (isUnrealCpp) {
          setupSteps.addAll([
            (
              label: 'Class',
              detail:
                  'New C++ Class (ACharacter) → $folderPath/PlayerCharacter',
            ),
            (
              label: 'Capsule',
              detail: 'GetCapsuleComponent()->InitCapsuleSize(35.f, 88.f)',
            ),
            (
              label: 'Camera',
              detail:
                  'CreateDefaultSubobject<UCameraComponent> → GetCapsuleComponent()',
            ),
          ]);
        } else if (isUnity) {
          setupSteps.addAll([
            (
              label: 'Prefab',
              detail:
                  'Create Empty PlayerCharacter → Save to $folderPath$assetName',
            ),
            (
              label: 'Collider',
              detail:
                  '+ Add ${is2D ? 'Rigidbody2D + CapsuleCollider2D' : 'CharacterController'} & PlayerController.cs',
            ),
            (
              label: 'Camera',
              detail: 'Add Child Camera → FirstPersonCamera at (0, 0.64, 0)',
            ),
          ]);
        } else {
          final bodyNode = is2D ? 'CharacterBody2D' : 'CharacterBody3D';
          final colNode = is2D ? 'CollisionShape2D' : 'CollisionShape3D';
          final camNode = is2D ? 'Camera2D' : 'Camera3D';
          setupSteps.addAll([
            (
              label: 'Scene',
              detail: '+ $bodyNode root → Save $folderPath$assetName',
            ),
            (
              label: 'Script',
              detail: '📜 Attach Script → player_character.gd',
            ),
            (
              label: 'Nodes',
              detail: '+ Add $colNode (CapsuleShape) & $camNode',
            ),
          ]);
        }
      } else if (archetype == 'ui') {
        if (isUnrealBp) {
          setupSteps.addAll([
            (
              label: 'Widget',
              detail: 'Widget Blueprint (User Widget) → $folderPath$assetName',
            ),
            (
              label: 'Root',
              detail: 'Designer → Drag Canvas Panel to root',
            ),
            (
              label: 'Control',
              detail:
                  'Palette → Drag ${activeTargetComp.componentKey} under Canvas Panel',
            ),
          ]);
        } else if (isUnrealCpp) {
          setupSteps.addAll([
            (
              label: 'Class',
              detail: 'New C++ Class (UUserWidget) → $folderPath$assetName',
            ),
            (
              label: 'Bind',
              detail:
                  'UPROPERTY(meta = (BindWidget)) ${activeTargetComp.componentKey}',
            ),
            (
              label: 'Init',
              detail: 'Override NativeConstruct() in .cpp',
            ),
          ]);
        } else if (isUnity) {
          setupSteps.addAll([
            (
              label: 'Canvas',
              detail: 'UI → Canvas ($pascalName) → Save to $folderPath',
            ),
            (
              label: 'Script',
              detail: '+ Add Component → ${pascalName}UI.cs',
            ),
            (
              label: 'Control',
              detail:
                  'Canvas → UI → Add ${activeTargetComp.componentKey}',
            ),
          ]);
        } else {
          setupSteps.addAll([
            (
              label: 'Scene',
              detail: 'Control root → Save $folderPath$assetName',
            ),
            (
              label: 'Script',
              detail: '📜 Attach Script → ${snakeName}_hud.gd',
            ),
            (
              label: 'Control',
              detail: '+ Add ${activeTargetComp.displayLabel}',
            ),
          ]);
        }
      } else if (archetype == 'level') {
        if (isUnreal) {
          setupSteps.addAll([
            (
              label: 'Map',
              detail: 'File → New Level (Basic) → Save $folderPath$assetName',
            ),
            (
              label: 'Pawn',
              detail:
                  'World Settings → Default Pawn Class = BP_PlayerCharacter',
            ),
            (
              label: 'Spawn',
              detail:
                  'Place Actors → PlayerStart at (0, 0, 120) above floor',
            ),
          ]);
        } else if (isUnity) {
          setupSteps.addAll([
            (
              label: 'Scene',
              detail:
                  'File → New Scene → Save $folderPath$assetName + ${activeTargetComp.displayLabel} at (0,0,0)',
            ),
            (
              label: 'Player',
              detail:
                  'Place PlayerCharacter (${is2D ? 'Rigidbody2D + CapsuleCollider2D' : 'CharacterController + gravity'})',
            ),
            (
              label: 'Spawn',
              detail: 'Transform Position = (0, 2, 0) above floor',
            ),
          ]);
        } else {
          final rootNode = is2D ? 'Node2D' : 'Node3D';
          final bodyNode = is2D ? 'CharacterBody2D' : 'CharacterBody3D';
          setupSteps.addAll([
            (
              label: 'Scene',
              detail:
                  'Create $rootNode → Save $folderPath$assetName + ${activeTargetComp.displayLabel} at (0,0,0)',
            ),
            (
              label: 'Player',
              detail:
                  'Instantiate player_character.tscn ($bodyNode + gravity)',
            ),
            (
              label: 'Spawn',
              detail: 'Place PlayerStart at (0, 2, 0) above floor',
            ),
          ]);
        }
      } else {
        if (isUnrealBp) {
          setupSteps.addAll([
            (
              label: 'Asset',
              detail: 'Blueprint Class (Actor) → $folderPath$assetName',
            ),
            (
              label: 'Component',
              detail: 'Components → + Add ${activeTargetComp.displayLabel}',
            ),
            if (needsPlayerSpawnSetup)
              (
                label: 'Spawn',
                detail:
                    'Default Pawn = BP_PlayerCharacter · PlayerStart at (0, 0, 120)',
              )
            else
              (
                label: 'Target',
                detail:
                    'Select ${activeTargetComp.componentKey} → Details & Event Graph',
              ),
          ]);
        } else if (isUnrealCpp) {
          setupSteps.addAll([
            (
              label: 'Class',
              detail: 'New C++ Class (AActor) → $folderPath$pascalName',
            ),
            (
              label: 'Header',
              detail:
                  'UPROPERTY(VisibleAnywhere) ${activeTargetComp.componentKey}',
            ),
            (
              label: 'Ctor',
              detail:
                  'CreateDefaultSubobject → ${activeTargetComp.componentKey}',
            ),
          ]);
        } else if (isUnity) {
          setupSteps.addAll([
            (
              label: 'Prefab',
              detail: 'Create Empty $pascalName → $folderPath$assetName',
            ),
            (
              label: 'Component',
              detail: '+ Add Component → ${activeTargetComp.displayLabel}',
            ),
            (
              label: 'Script',
              detail: '+ Add Component → ${pascalName}Controller.cs',
            ),
          ]);
        } else {
          final rootNode = is2D ? 'Node2D' : 'Node3D';
          setupSteps.addAll([
            (
              label: 'Scene',
              detail: 'Create $rootNode → Save $folderPath$assetName',
            ),
            (
              label: 'Script',
              detail: '📜 Attach Script → $snakeName.gd',
            ),
            (
              label: 'Child',
              detail: '+ Add ${activeTargetComp.displayLabel}',
            ),
          ]);
        }
      }
    } else {
      setupSteps.addAll([
        (
          label: archetype == 'level' ? 'Map' : 'Asset',
          detail: 'Open $folderPath$assetName',
        ),
        (
          label: 'Select',
          detail:
              '${activeTargetComp.displayLabel} in ${archetype == 'level' ? (isUnreal ? 'World Outliner' : (isUnity ? 'Hierarchy' : 'Scene Tree')) : (isUnrealBp ? 'Components' : (isUnrealCpp ? 'Subobjects' : (isUnity ? 'Hierarchy' : 'Scene Dock')))}',
        ),
      ]);
    }

    final levelHookupTitle = needsPlayerSpawnSetup
        ? (isUnreal
            ? '🗺 LEVEL & PLAYER START SETUP'
            : (isUnity
                ? '🗺 SCENE & PLAYER SPAWN SETUP'
                : '🗺 MAIN SCENE & PLAYER SPAWN SETUP'))
        : (isUnreal
            ? '🗺 LEVEL SETUP'
            : (isUnity ? '🗺 SCENE SETUP' : '🗺 MAIN SCENE SETUP'));
    final levelHookupSteps = <String>[];
    if (selectedTaskIdx == 0 && checkpointIndex == 0) {
      if (archetype == 'character') {
        if (isUnrealBp) {
          levelHookupSteps.addAll([
            'World Settings → GameMode Override → Set Default Pawn Class = $assetName',
            'Place Actors → Drag a PlayerStart onto the level floor (Z = 90)',
          ]);
        } else if (isUnrealCpp) {
          levelHookupSteps.addAll([
            'GameMode Constructor → Set DefaultPawnClass = $assetName::StaticClass();',
            'Level Viewport → Place a PlayerStart actor on the floor (Z = 90)',
          ]);
        } else if (isUnity) {
          levelHookupSteps.addAll([
            'Project Window → Drag $assetName from $folderPath into the active Scene Hierarchy',
            'Inspector → Transform → Set Position = (0, 1, 0) above the floor collider',
          ]);
        } else {
          levelHookupSteps.addAll([
            'Main Level Scene → Click Instantiate Child Scene (🔗) in Scene Dock → Select $assetName',
            'Inspector → Transform → Set Position = (0, 1, 0) above the floor collision',
          ]);
        }
      } else if (archetype == 'ui') {
        if (isUnrealBp) {
          levelHookupSteps.addAll([
            'Open BP_PlayerCharacter → Event BeginPlay → Call Create Widget (Class: $assetName)',
            'Wire Return Value → Add to Viewport',
          ]);
        } else if (isUnrealCpp) {
          levelHookupSteps.addAll([
            'In BeginPlay(), call CreateWidget<UUserWidget>(GetWorld(), ${assetName}Class)',
            'Call ->AddToViewport() on the created widget instance',
          ]);
        } else if (isUnity) {
          levelHookupSteps.addAll([
            'Project Window → Drag $assetName from $folderPath into the active Scene Hierarchy',
            'Hierarchy Window → Verify an EventSystem object is present in the scene',
          ]);
        } else {
          levelHookupSteps.addAll([
            'Main Level Scene → Add a CanvasLayer node if not already present',
            'Click Instantiate Child Scene (🔗) under CanvasLayer → Select $assetName',
          ]);
        }
      } else if (archetype == 'level') {
        if (isUnreal) {
          levelHookupSteps.addAll([
            'World Outliner ($assetName) → Place ${activeTargetComp.componentKey} at Location = (0, 0, 0) with BlockAll collision',
            'World Settings → GameMode Override → Set Default Pawn Class = BP_PlayerCharacter (ACharacter with CapsuleComponent & gravity)',
            'Place Actors → Position PlayerStart at Location = (0, 0, 120) above ${activeTargetComp.componentKey} so the player character lands firm on Play',
          ]);
        } else if (isUnity) {
          levelHookupSteps.addAll([
            'Scene Hierarchy ($assetName) → Verify ${activeTargetComp.componentKey} is at Position = (0, 0, 0) with Collider attached',
            'Hierarchy → Place PlayerCharacter with CharacterController / Rigidbody at Position = (0, 2, 0) above the floor',
          ]);
        } else {
          levelHookupSteps.addAll([
            'Scene Tree ($assetName) → Verify ${activeTargetComp.componentKey} is at Position = (0, 0, 0) with CollisionShape attached',
            'Scene Tree → Instantiate player_character.tscn at Position = (0, 2, 0) above the floor so the character lands firm on Play',
          ]);
        }
      } else {
        if (isUnrealBp) {
          levelHookupSteps.addAll([
            'Content Browser ($folderPath) → Drag $assetName into the Level Viewport',
            'Details Panel → Transform → Set Location = (0, 0, 0)',
            if (needsPlayerSpawnSetup)
              'World Settings → Set Default Pawn Class = BP_PlayerCharacter and place PlayerStart at Location = (0, 0, 120) above $assetName',
          ]);
        } else if (isUnrealCpp) {
          levelHookupSteps.addAll([
            'Place Actors / Outliner → Place an instance of $assetName in the Level Viewport',
            'Details Panel → Transform → Set Location = (0, 0, 0)',
            if (needsPlayerSpawnSetup)
              'World Settings → Set DefaultPawnClass = APlayerCharacter::StaticClass() and place PlayerStart at Location = (0, 0, 120)',
          ]);
        } else if (isUnity) {
          levelHookupSteps.addAll([
            'Project Window ($folderPath) → Drag $assetName into the active Scene Hierarchy',
            'Inspector → Transform → Set Position = (0, 0, 0)',
            if (needsPlayerSpawnSetup)
              'Scene Hierarchy → Place PlayerCharacter at Position = (0, 2, 0) above $assetName',
          ]);
        } else {
          levelHookupSteps.addAll([
            'Main Level Scene → Click Instantiate Child Scene (🔗) in Scene Dock → Select $assetName',
            'Inspector → Transform → Set Position = (0, 0, 0)',
            if (needsPlayerSpawnSetup)
              'Main Level Scene → Instantiate player_character.tscn at Position = (0, 2, 0) above $assetName',
          ]);
        }
      }
    }

    return (
      archetype: archetype,
      is2D: is2D,
      sec1Title: sec1Title,
      sec2Title: sec2Title,
      sec3Title: sec3Title,
      assetIcon: assetIcon,
      assetName: assetName,
      parentClassLabel: parentClassLabel,
      folderPath: folderPath,
      isNewAssetOnTask: isNewAssetOnTask,
      setupSteps: setupSteps,
      levelHookupTitle: levelHookupTitle,
      levelHookupSteps: levelHookupSteps,
    );
  }

  /// Extracts up to 2 short, scannable bullet items for a left-column `02 BUILD TASKS` card
  /// so the card lists concrete items instead of a truncated prose sentence.
  List<String> _extractTaskCardBullets(
    TaskHowToBlueprint bp,
    String groupTitle,
  ) {
    final bullets = <String>[];
    final lowerTitle = groupTitle.trim().toLowerCase();

    // 1. Prefer distinct sub-step titles if the task has multiple sub-steps
    for (final s in bp.subSteps) {
      final clean = s.shortTitle.trim();
      if (clean.isNotEmpty &&
          clean.toLowerCase() != lowerTitle &&
          !bullets.any((b) => b.toLowerCase() == clean.toLowerCase())) {
        bullets.add(clean);
        if (bullets.length >= 2) return bullets;
      }
    }

    // 2. Otherwise split the task goal sentence into 2 concise clause bullets (stripping prose verbs & trailing asset suffix)
    final strippedGoal = bp.taskGoalSentence
        .replaceAll(
          RegExp(
            r'^(?:configure|implement|create|add|build|wire|setup|set up|bind|establish|define|update)\s+(?:the\s+)?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\s+in\s+(?:BP_|WBP_|A|U)?[A-Za-z0-9_.]+\.?\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\.\s*$'), '')
        .trim();

    if (strippedGoal.isNotEmpty) {
      final rawParts = strippedGoal
          .split(RegExp(r',\s*(?:and\s+)?|\s+and\s+'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      for (final part in rawParts) {
        final capitalized =
            part[0].toUpperCase() + (part.length > 1 ? part.substring(1) : '');
        if (capitalized.toLowerCase() != lowerTitle &&
            !bullets.any((b) => b.toLowerCase() == capitalized.toLowerCase())) {
          bullets.add(capitalized);
          if (bullets.length >= 2) break;
        }
      }
    }

    if (bullets.isEmpty && bp.subSteps.isNotEmpty) {
      bullets.add(bp.subSteps.first.shortTitle);
    }
    return bullets;
  }

  /// Infers the specific owning component name and engine Details/Inspector category for a property row
  /// so Capsule, Camera, and Movement properties are never misattributed to a single component.
  ({String componentLabel, String categoryLabel, String propertyLabel})
      _inferOwningComponentForProperty({
    required String rawKey,
    required String defaultComponentKey,
    required String engineLabel,
    required bool is2D,
  }) {
    final isUnreal = engineLabel.contains('UNREAL');
    final isUnity = engineLabel.contains('UNITY');
    String defaultCatFor(String comp) {
      final lc = comp.toLowerCase();
      if (lc.contains('capsule') ||
          lc.contains('collider') ||
          lc.contains('collisionshape')) {
        return isUnreal
            ? 'Category: Shape'
            : (isUnity
                ? 'Collider Bounds'
                : 'Shape: ${is2D ? 'CapsuleShape2D' : 'CapsuleShape3D'}');
      }
      if (lc.contains('camera') || lc.contains('springarm')) {
        return isUnreal
            ? 'Category: Camera Settings'
            : (isUnity ? 'Camera Projection' : 'Node: Camera Transform');
      }
      if (lc.contains('movement') ||
          lc.contains('rigidbody') ||
          lc.contains('characterbody')) {
        return isUnreal
            ? 'Category: Character Movement'
            : (isUnity
                ? '[SerializeField] Tuning'
                : 'Script Variables (@export)');
      }
      return isUnreal
          ? 'Category: Details'
          : (isUnity ? 'Component Settings' : 'Inspector Properties');
    }

    for (final sep in const ['→', '›', '·']) {
      final idx = rawKey.indexOf(sep);
      if (idx > 0 && idx < rawKey.length - 1) {
        final left = rawKey.substring(0, idx).trim();
        final right = rawKey.substring(idx + 1).trim();
        if (left.toLowerCase() != 'tuning' &&
            left.toLowerCase() != 'inspector') {
          return (
            componentLabel: left,
            categoryLabel: defaultCatFor(left),
            propertyLabel: right,
          );
        }
        return (
          componentLabel: defaultComponentKey,
          categoryLabel: defaultCatFor(defaultComponentKey),
          propertyLabel: right,
        );
      }
    }

    final lower = rawKey.toLowerCase();
    if (lower.contains('capsule') ||
        lower.contains('radius') ||
        lower.contains('halfheight') ||
        lower == 'height') {
      final comp = isUnreal
          ? 'CapsuleComponent'
          : (isUnity
              ? (is2D ? 'CapsuleCollider2D' : 'CharacterController')
              : (is2D ? 'CollisionShape2D' : 'CollisionShape3D'));
      return (
        componentLabel: comp,
        categoryLabel: defaultCatFor(comp),
        propertyLabel: rawKey,
      );
    }
    if (lower.contains('camera') ||
        lower.contains('fov') ||
        lower.contains('pitch') ||
        lower.contains('eye') ||
        lower.contains('fade') ||
        lower.contains('springarm')) {
      final comp = isUnreal
          ? 'FirstPersonCamera'
          : (isUnity ? 'MainCamera' : (is2D ? 'Camera2D' : 'Camera3D'));
      return (
        componentLabel: comp,
        categoryLabel: defaultCatFor(comp),
        propertyLabel: rawKey,
      );
    }
    if (lower.contains('walkspeed') ||
        lower.contains('maxwalk') ||
        lower.contains('jumpz') ||
        lower.contains('aircontrol') ||
        lower.contains('braking') ||
        lower.contains('groundfriction') ||
        lower.contains('maxacceleration') ||
        lower.contains('gravity')) {
      final comp = isUnreal
          ? 'CharacterMovement'
          : (isUnity ? 'PlayerController.cs' : 'CharacterBody');
      return (
        componentLabel: comp,
        categoryLabel: defaultCatFor(comp),
        propertyLabel: rawKey,
      );
    }
    return (
      componentLabel: defaultComponentKey,
      categoryLabel: defaultCatFor(defaultComponentKey),
      propertyLabel: rawKey,
    );
  }

  /// Groups all `[T]` Tasks in the checkpoint by their target scene component so shared components
  /// appear once in Section `01` with `[T1]`, `[T2] [T3]` badges.
  List<
      ({
        String icon,
        String componentKey,
        String displayLabel,
        List<int> taskIndices,
      })> _buildPersistentSceneTreeComponents(
    List<TaskHowToBlueprint> howToBlueprints, {
    required bool unrealCppMode,
  }) {
    final grouped = <({
      String icon,
      String componentKey,
      String displayLabel,
      List<int> taskIndices,
    })>[];
    for (int tIdx = 0; tIdx < howToBlueprints.length; tIdx++) {
      final resolved = _resolveTaskTargetComponent(
        howToBlueprints[tIdx],
        unrealCppMode: unrealCppMode,
      );
      final existingIdx = grouped.indexWhere(
        (g) =>
            g.componentKey.toLowerCase() ==
            resolved.componentKey.toLowerCase(),
      );
      if (existingIdx != -1) {
        grouped[existingIdx].taskIndices.add(tIdx);
      } else {
        grouped.add((
          icon: resolved.icon,
          componentKey: resolved.componentKey,
          displayLabel: resolved.displayLabel,
          taskIndices: <int>[tIdx],
        ));
      }
    }
    return grouped;
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
                                              '02 · BUILD TASKS',
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

                                      // ── B. Prior Checkpoints Stack & Scheduled Inbox Compatibility Hooks (Reclaims 42px top banner space) ──
                                      SizedBox(
                                        height: 1,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Opacity(
                                            opacity: 0,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                for (int cpIdx = 0;
                                                    cpIdx < states.length;
                                                    cpIdx++)
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
                                                    child: Text(
                                                      'CP${cpIdx + 1} · ${states[cpIdx].releaseVersion}',
                                                    ),
                                                  ),
                                                for (final upg
                                                    in scheduledUpgrades)
                                                  InkWell(
                                                    key: ValueKey(
                                                      'outline_scheduled_inbox_chip_${feat.id}_${upg.id}',
                                                    ),
                                                    onTap: () =>
                                                        _showFeatureInboxModal(
                                                      context,
                                                    ),
                                                    child: Text(
                                                      '🗓 Queued · ${upg.targetFuturePhase.shortName}',
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
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

                                      // ── C & D. 100% Full-Width Active Task Runbook Sheet (Tasks Moved to Far-Left Outliner Rail) ──
                                      if (howToBlueprints.isNotEmpty)
                                        Builder(
                                          builder: (context) {
                                            final activeBp = selectedHowTo;
                                            final totalSubCount =
                                                activeBp.subSteps.length;
                                            final bool mountFallbackTaskKeys =
                                                isHalfScreenOverlayMode &&
                                                    !_isHalfScreenOutlinerOpen;

                                            // Zero-height compatibility hooks for feature brief, non-active task steps, and half-screen closed-drawer task keys
                                            final compatibilityHooksRow =
                                                SizedBox(
                                              height: 1,
                                              child: SingleChildScrollView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: Opacity(
                                                  opacity: 0,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      featureBriefCardWidget,
                                                      for (int tIdx = 0;
                                                          tIdx <
                                                              howToBlueprints
                                                                  .length;
                                                          tIdx++) ...[
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
                                                            final groupTitle = bp
                                                                .shortTaskTitle;
                                                            return Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                if (mountFallbackTaskKeys) ...[
                                                                  if (_activeStage2InlineEditKey ==
                                                                      'edit_task_${node.id}_$tIdx')
                                                                    SizedBox(
                                                                      width:
                                                                          180,
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
                                                                      ),
                                                                    ),
                                                                  InkWell(
                                                                    key: ValueKey(
                                                                      'outline_task_${node.id}_$tIdx',
                                                                    ),
                                                                    onTap: () {
                                                                      _rebuild(
                                                                          () {
                                                                        _manualCheckpointFocusIndex =
                                                                            index;
                                                                        _manualCheckpointFocusFeatureId =
                                                                            feat.id;
                                                                        _selectedTaskIndexByCheckpoint[
                                                                            node.id] = tIdx;
                                                                        final firstIncomplete = task
                                                                            .children
                                                                            .indexWhere((c) => !c.completed);
                                                                        _selectedSubStepIndexByTask['${node.id}_$tIdx'] = firstIncomplete != -1
                                                                            ? firstIncomplete
                                                                            : 0;
                                                                      });
                                                                    },
                                                                    child: Text(
                                                                      groupTitle,
                                                                    ),
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
                                                                    child: const Text(
                                                                      'T',
                                                                    ),
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
                                                                    child: const Text(
                                                                      '✎',
                                                                    ),
                                                                  ),
                                                                ],
                                                                InkWell(
                                                                  key: ValueKey(
                                                                    'outline_task_chevron_${node.id}_$tIdx',
                                                                  ),
                                                                  onTap: () =>
                                                                      _rebuild(
                                                                          () {}),
                                                                  child: const SizedBox(
                                                                    width: 4,
                                                                    height: 1,
                                                                  ),
                                                                ),
                                                                if (!isTaskActive)
                                                                  for (int sIdx =
                                                                          0;
                                                                      sIdx <
                                                                          bp
                                                                              .subSteps
                                                                              .length;
                                                                      sIdx++) ...[
                                                                    InkWell(
                                                                      key: ValueKey(
                                                                        'playlist_step_row_${node.id}_${tIdx}_$sIdx',
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
                                                                          _selectedSubStepIndexByTask['${node.id}_$tIdx'] =
                                                                              sIdx;
                                                                        });
                                                                      },
                                                                      child: const SizedBox(
                                                                        width:
                                                                            4,
                                                                        height:
                                                                            1,
                                                                      ),
                                                                    ),
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
                                                                          _selectedTaskIndexByCheckpoint[node.id] =
                                                                              tIdx;
                                                                          _selectedSubStepIndexByTask['${node.id}_$tIdx'] =
                                                                              sIdx;
                                                                        });
                                                                      },
                                                                      child: const SizedBox(
                                                                        width:
                                                                            4,
                                                                        height:
                                                                            1,
                                                                      ),
                                                                    ),
                                                                    InkWell(
                                                                      key: ValueKey(
                                                                        'toggle_step_mark_${node.id}_${tIdx}_$sIdx',
                                                                      ),
                                                                      onTap: () =>
                                                                          _toggleHowToSubStepCompletion(
                                                                        feat,
                                                                        states,
                                                                        node,
                                                                        tIdx,
                                                                        sIdx,
                                                                      ),
                                                                      child: const SizedBox(
                                                                        width:
                                                                            4,
                                                                        height:
                                                                            1,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                Text(
                                                                  'T$globalNumLabel',
                                                                ),
                                                                Text(
                                                                  globalNumLabel,
                                                                ),
                                                                Text(
                                                                  'TASK $globalNumLabel · ${groupTitle.toUpperCase()}',
                                                                ),
                                                                Text(
                                                                  '$doneSubCount/$taskSubCount',
                                                                ),
                                                                Text(
                                                                  isTaskActive
                                                                      ? ' ▾'
                                                                      : ' ▸',
                                                                ),
                                                                for (int sIdx =
                                                                        0;
                                                                    sIdx <
                                                                        bp
                                                                            .subSteps
                                                                            .length;
                                                                    sIdx++) ...[
                                                                  Text(
                                                                    '${sIdx + 1}. ${bp.subSteps[sIdx].shortTitle} ${bp.subSteps[sIdx].etaLabel}',
                                                                  ),
                                                                  Text(
                                                                    bp.subSteps[sIdx]
                                                                            .subtask
                                                                            .completed
                                                                        ? '✓ '
                                                                        : (isTaskActive &&
                                                                                sIdx ==
                                                                                    effectiveSubStepIdx
                                                                            ? '▶ '
                                                                            : '○ '),
                                                                  ),
                                                                ],
                                                                Text(
                                                                  bp.taskGoalSentence,
                                                                ),
                                                              ],
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                      if (mountFallbackTaskKeys) ...[
                                                        if (_activeStage2InlineEditKey ==
                                                            'add_task_${node.id}')
                                                          SizedBox(
                                                            width: 220,
                                                            child:
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
                                                                  'Add build task...',
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
                                                          InkWell(
                                                            key: ValueKey(
                                                              'outline_add_task_btn_${node.id}',
                                                            ),
                                                            onTap: () =>
                                                                _startStage2InlineEdit(
                                                              'add_task_${node.id}',
                                                              '',
                                                            ),
                                                            child: const Text(
                                                              '+ Add Build Task...',
                                                            ),
                                                          ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );

                                            // ── Active Task Implementation Sheet (100% Full Width · #121620 30% Cool Gunmetal Slate Sheet) ──
                                            final isLastTaskInFeature =
                                                selectedTaskIdx >=
                                                    howToBlueprints.length - 1;
                                            final isSelectedTaskCompleted =
                                                selectedTaskIdx <
                                                        node.checklist.length &&
                                                    node
                                                        .checklist[
                                                            selectedTaskIdx]
                                                        .completed;
                                            final isDrawerOpen =
                                                _inlineBugDrawerNodeId ==
                                                    node.id;
                                            final verifySentenceText = activeBp
                                                    .taskDoneCheck
                                                    .trim()
                                                    .isNotEmpty
                                                ? activeBp.taskDoneCheck.trim()
                                                : activeSubStep.verifyResult
                                                    .trim();

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
                                                  // 1. Sheet Header (Fixed Row 1 · 42px · #161B26)
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
                                                                          0.40,
                                                                    ),
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  'T${selectedTaskIdx + 1}',
                                                                  style: GoogleFonts
                                                                      .jetBrainsMono(
                                                                    fontSize:
                                                                        10.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                    color: const Color(
                                                                      0xFF38BDF8,
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
                                                                  selectedHowTo
                                                                      .shortTaskTitle,
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
                                                              onTap: (activeSubStep
                                                                          .subtask
                                                                          .completed ||
                                                                      !isLastTaskInFeature)
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
                                                                  color: (activeSubStep
                                                                              .subtask
                                                                              .completed ||
                                                                          !isLastTaskInFeature)
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
                                                                    color: (activeSubStep
                                                                                .subtask
                                                                                .completed ||
                                                                            !isLastTaskInFeature)
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
                                                                    color: (activeSubStep
                                                                                .subtask
                                                                                .completed ||
                                                                            !isLastTaskInFeature)
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

                                                  // 2. Fixed Top Verify in Engine Bar (Row 2 · #121620 · 0px Vertical Jump)
                                                  Container(
                                                    key: ValueKey(
                                                      'task_overview_goal_box_${node.id}_$selectedTaskIdx',
                                                    ),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 14,
                                                      vertical: 8,
                                                    ),
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: Color(0xFF121620),
                                                      border: Border(
                                                        bottom: BorderSide(
                                                          color:
                                                              Color(0xFF262E40),
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
                                                                Text('Done'),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                        LayoutBuilder(
                                                          builder: (
                                                            context,
                                                            barCons,
                                                          ) {
                                                            final isCompactBar =
                                                                isHalfScreenOverlayMode ||
                                                                    barCons.maxWidth <
                                                                        520;
                                                            final verifyRow =
                                                                Row(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Container(
                                                                  padding:
                                                                      const EdgeInsets
                                                                          .symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical: 2,
                                                                  ),
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: const Color(
                                                                      0xFF10B981,
                                                                    ).withValues(
                                                                      alpha:
                                                                          0.14,
                                                                    ),
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                      4,
                                                                    ),
                                                                    border: Border
                                                                        .all(
                                                                      color: const Color(
                                                                        0xFF10B981,
                                                                      ).withValues(
                                                                        alpha:
                                                                            0.38,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  child: Text(
                                                                    '✓ Verify in engine',
                                                                    style: GoogleFonts
                                                                        .jetBrainsMono(
                                                                      fontSize:
                                                                          10,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      color: const Color(
                                                                        0xFF34D399,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 8,
                                                                ),
                                                                Expanded(
                                                                  child: Text
                                                                      .rich(
                                                                    _buildSemanticStepSpan(
                                                                      text:
                                                                          verifySentenceText,
                                                                      baseStyle:
                                                                          GoogleFonts
                                                                              .inter(
                                                                        fontSize:
                                                                            12.5,
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .w500,
                                                                        height:
                                                                            1.35,
                                                                        color: const Color(
                                                                          0xFFD1FAE5,
                                                                        ),
                                                                      ),
                                                                      tuningItems:
                                                                          tuningItems,
                                                                      edgeItems:
                                                                          edgeItems,
                                                                      isCodeBlock:
                                                                          false,
                                                                    ),
                                                                    maxLines: 2,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                              ],
                                                            );

                                                            final issueBtn =
                                                                InkWell(
                                                              key: ValueKey(
                                                                'feature_gate_log_bug_btn_${node.id}',
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                6,
                                                              ),
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
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 6,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: isDrawerOpen
                                                                      ? const Color(
                                                                          0xFFFBBF24,
                                                                        ).withValues(
                                                                          alpha:
                                                                              0.14,
                                                                        )
                                                                      : const Color(
                                                                          0xFF181E2C,
                                                                        ),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    6,
                                                                  ),
                                                                  border:
                                                                      Border.all(
                                                                    color: isDrawerOpen
                                                                        ? const Color(
                                                                            0xFFFBBF24,
                                                                          ).withValues(
                                                                            alpha:
                                                                                0.45,
                                                                          )
                                                                        : const Color(
                                                                            0xFF262E40,
                                                                          ),
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  '⚑ Issue',
                                                                  style: GoogleFonts
                                                                      .inter(
                                                                    fontSize:
                                                                        11.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: isDrawerOpen
                                                                        ? const Color(
                                                                            0xFFFBBF24,
                                                                          )
                                                                        : const Color(
                                                                            0xFF94A3B8,
                                                                          ),
                                                                  ),
                                                                ),
                                                              ),
                                                            );

                                                            final doneBtn =
                                                                InkWell(
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
                                                                      .circular(
                                                                6,
                                                              ),
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal:
                                                                      13,
                                                                  vertical: 6,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: (activeSubStep
                                                                              .subtask
                                                                              .completed ||
                                                                          isSelectedTaskCompleted)
                                                                      ? const Color(
                                                                          0xFF10B981,
                                                                        ).withValues(
                                                                          alpha:
                                                                              0.18,
                                                                        )
                                                                      : const Color(
                                                                          0xFF10B981,
                                                                        ),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    6,
                                                                  ),
                                                                  border:
                                                                      Border.all(
                                                                    color: (activeSubStep
                                                                                .subtask
                                                                                .completed ||
                                                                            isSelectedTaskCompleted)
                                                                        ? const Color(
                                                                            0xFF10B981,
                                                                          ).withValues(
                                                                            alpha:
                                                                                0.45,
                                                                          )
                                                                        : const Color(
                                                                            0xFF34D399,
                                                                          ),
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  (activeSubStep
                                                                              .subtask
                                                                              .completed ||
                                                                          isSelectedTaskCompleted)
                                                                      ? '✓ Verified'
                                                                      : (isHalfScreenOverlayMode
                                                                          ? 'Done & Next →'
                                                                          : (isLastTaskInFeature
                                                                              ? '✓ Complete Feature & Next →'
                                                                              : 'Done & Next Task →')),
                                                                  style: GoogleFonts
                                                                      .inter(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: (activeSubStep
                                                                                .subtask
                                                                                .completed ||
                                                                            isSelectedTaskCompleted)
                                                                        ? const Color(
                                                                            0xFF6EE7B7,
                                                                          )
                                                                        : const Color(
                                                                            0xFF042F2E,
                                                                          ),
                                                                  ),
                                                                ),
                                                              ),
                                                            );

                                                            if (isCompactBar) {
                                                              return Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .stretch,
                                                                children: [
                                                                  verifyRow,
                                                                  const SizedBox(
                                                                    height: 8,
                                                                  ),
                                                                  Row(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .end,
                                                                    children: [
                                                                      issueBtn,
                                                                      const SizedBox(
                                                                        width:
                                                                            8,
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
                                                                  child:
                                                                      verifyRow,
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
                                                      ],
                                                    ),
                                                  ),

                                                  // 2b. Top Inline Bug Drawer (Opens directly below Row 2 when ⚑ Issue is clicked)
                                                  if (isDrawerOpen)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.fromLTRB(
                                                        14,
                                                        10,
                                                        14,
                                                        10,
                                                      ),
                                                      decoration:
                                                          const BoxDecoration(
                                                        color:
                                                            Color(0xFF191412),
                                                        border: Border(
                                                          bottom: BorderSide(
                                                            color: Color(
                                                              0x4DF59E0B,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Text(
                                                            'Log Playtest Issue:',
                                                            style: GoogleFonts
                                                                .inter(
                                                              fontSize: 11.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color:
                                                                  const Color(
                                                                0xFFFBBF24,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 10,
                                                          ),
                                                          Expanded(
                                                            child: TextField(
                                                              key: ValueKey(
                                                                'feature_gate_bug_input_${node.id}',
                                                              ),
                                                              controller:
                                                                  _inlineBugInputCtrl,
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontSize: 12.5,
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
                                                                  fontSize: 12,
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
                                                                  vertical: 8,
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
                                                              onSubmitted: (_) =>
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
                                                                horizontal: 12,
                                                                vertical: 8,
                                                              ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color:
                                                                    const Color(
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
                                                                  color:
                                                                      const Color(
                                                                    0xFFFBBF24,
                                                                  ).withValues(
                                                                    alpha: 0.45,
                                                                  ),
                                                                ),
                                                              ),
                                                              child: Text(
                                                                '+ Add [FIX] Task',
                                                                style:
                                                                    GoogleFonts
                                                                        .inter(
                                                                  fontSize:
                                                                      11.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color:
                                                                      const Color(
                                                                    0xFFFBBF24,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),

                                                  // 3. Pure Step -> Code Accordion Runbook Body
                                                  _buildEngineStepAreasBox(
                                                    feat: feat,
                                                    states: states,
                                                    checkpointIndex: index,
                                                    node: node,
                                                    howToBlueprints:
                                                        howToBlueprints,
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

                                                  // Zero-size compatibility hooks for step/gate actions
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
                                                              'feature_step_log_bug_btn_${node.id}',
                                                            ),
                                                            onTap: () =>
                                                                _showLogPlaytestIssueDialog(
                                                              feat,
                                                              states,
                                                              index,
                                                            ),
                                                            child: const Text(
                                                              'Issue',
                                                            ),
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

                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                compatibilityHooksRow,
                                                rightDockWidget,
                                              ],
                                            );
                                          },
                                        ),

                                      // ── E. Zero-Height Playtest Gate Compatibility Hook (Replaces duplicate bottom gate) ──
                                      SizedBox(
                                        key: ValueKey(
                                          'feature_playtest_gate_card_${node.id}',
                                        ),
                                        height: 1,
                                        child: Opacity(
                                          opacity: 0,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              InkWell(
                                                key: ValueKey(
                                                  'feature_gate_pass_btn_${node.id}',
                                                ),
                                                onTap: () {
                                                  _passCheckpointPlaytestAndAdvance(
                                                    feat,
                                                    states,
                                                    node,
                                                  );
                                                },
                                                child: const Text(
                                                  'Pass Playtest & Continue →',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
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
