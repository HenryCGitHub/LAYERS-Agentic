part of 'release_workbench_screen.dart';

extension _WorkbenchCheckpointWorkspaceExt on _ReleaseWorkbenchScreenState {
  void _materializeUnifiedStepsIfNeeded(
    FeatureStateNode node,
    List<TaskHowToSubStep> unifiedSteps,
  ) {
    node.flattenLegacyNestedChecklistIfNeeded();
    final needsSync = node.checklist.length != unifiedSteps.length ||
        [
          for (int i = 0; i < unifiedSteps.length; i++)
            !identical(node.checklist[i], unifiedSteps[i].subtask),
        ].any((mismatch) => mismatch);
    if (needsSync && unifiedSteps.isNotEmpty) {
      node.checklist
        ..clear()
        ..addAll(unifiedSteps.map((s) => s.subtask));
    }
  }

  void _completeAllCheckpointTasks(FeatureStateNode node) {
    final steps = TaskHowToBlueprint.resolveUnifiedSteps(
      checkpointNode: node,
      engineHint: _engineHint,
      phase: widget.workbench.currentPhase,
    );
    _materializeUnifiedStepsIfNeeded(node, steps);
    for (final task in node.checklist) {
      task.completed = true;
      for (final child in task.children) {
        child.completed = true;
      }
    }
    node.isPlaytestPassed = true;
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
      _playtestGateActiveCheckpoints.remove(node.id);
      _inlineBugDrawerNodeId = null;
      if (nextCpIdx != -1) {
        _manualCheckpointFocusIndex = nextCpIdx;
        _manualCheckpointFocusFeatureId = feat.id;
        final nextCp = states[nextCpIdx];
        _playtestGateActiveCheckpoints.remove(nextCp.id);
        _selectedFlatStepIndexByCheckpoint[nextCp.id] = 0;
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

  void _completeCurrentFlatStepAndAdvance(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
    List<TaskHowToSubStep> unifiedSteps,
    int stepIdx,
  ) {
    if (unifiedSteps.isEmpty || stepIdx < 0 || stepIdx >= unifiedSteps.length) {
      return;
    }
    _materializeUnifiedStepsIfNeeded(node, unifiedSteps);
    unifiedSteps[stepIdx].subtask.completed = true;

    int nextIncomplete = -1;
    for (int i = stepIdx + 1; i < unifiedSteps.length; i++) {
      if (!unifiedSteps[i].subtask.completed) {
        nextIncomplete = i;
        break;
      }
    }
    if (nextIncomplete == -1) {
      nextIncomplete = unifiedSteps.indexWhere((s) => !s.subtask.completed);
    }

    final cpIdx = states.indexWhere((s) => s.id == node.id);
    _rebuild(() {
      if (cpIdx != -1) {
        _manualCheckpointFocusIndex = cpIdx;
        _manualCheckpointFocusFeatureId = feat.id;
      }
      if (nextIncomplete != -1) {
        _playtestGateActiveCheckpoints.remove(node.id);
        _awaitingPlaytestVerification.remove(node.id);
        _selectedFlatStepIndexByCheckpoint[node.id] = nextIncomplete;
      } else {
        _selectedFlatStepIndexByCheckpoint[node.id] = stepIdx;
        _playtestGateActiveCheckpoints.add(node.id);
        _awaitingPlaytestVerification.add(node.id);
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);
  }

  void _jumpToNextIncompleteStep(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
  ) {
    final steps = TaskHowToBlueprint.resolveUnifiedSteps(
      checkpointNode: node,
      engineHint: _engineHint,
      phase: widget.workbench.currentPhase,
    );
    final incompleteIdx = steps.indexWhere((s) => !s.subtask.completed);
    if (incompleteIdx != -1) {
      _selectFlatStep(node.id, incompleteIdx);
      return;
    }

    final activeVer = widget.workbench.activeReleaseVersionTag;
    int nextCpIdx = states.indexWhere(
      (s) => s.releaseVersion == activeVer && !s.isCompleted,
    );
    if (nextCpIdx == -1 && widget.workbench.getDocumentProgress(feat.id) < 100) {
      nextCpIdx = states.indexWhere((s) => !s.isCompleted);
    }
    if (nextCpIdx != -1) {
      final nextCp = states[nextCpIdx];
      final nextSteps = TaskHowToBlueprint.resolveUnifiedSteps(
        checkpointNode: nextCp,
        engineHint: _engineHint,
        phase: widget.workbench.currentPhase,
      );
      int targetIdx = nextSteps.indexWhere((s) => !s.subtask.completed);
      if (targetIdx == -1) targetIdx = 0;
      _rebuild(() {
        _manualCheckpointFocusIndex = nextCpIdx;
        _manualCheckpointFocusFeatureId = feat.id;
        _playtestGateActiveCheckpoints.remove(nextCp.id);
        _selectedFlatStepIndexByCheckpoint[nextCp.id] = targetIdx;
      });
      return;
    }

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
    required int activeStepIdx,
    required String rawValue,
    int? tuningParamIndex,
    String? propertyKey,
  }) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return;

    final tuningItems = node.tuningParams;
    int? resolvedMatchIdx;
    int targetIdx =
        tuningItems.isNotEmpty ? (activeStepIdx % tuningItems.length) : 0;
    if (tuningParamIndex != null &&
        tuningParamIndex >= 0 &&
        tuningParamIndex < tuningItems.length) {
      resolvedMatchIdx = tuningParamIndex;
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
        resolvedMatchIdx = matchedIdx;
        targetIdx = matchedIdx;
      }
    }

    final parts = trimmed.split(
      _ReleaseWorkbenchScreenState._tuningVarDelimiterRegex,
    );
    final valOnly = parts.length > 1
        ? parts.sublist(1).join(':').trim()
        : trimmed;

    if (propertyKey != null && propertyKey.isNotEmpty) {
      _customComponentPropertyOverrides['${node.id}::$propertyKey'] = valOnly;
      // Built-in engine properties (Position, Wait Time, Radius) that don't match
      // an @export tuningParam keep their override without clobbering unrelated vars.
      if (resolvedMatchIdx == null) {
        widget.workbench.updateFeatureStates(feat.id, states);
        _rebuild();
        return;
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

    if (tuningItems.isNotEmpty) {
      node.tuningParams[targetIdx] = trimmed;
    } else {
      node.tuningParams.add(trimmed);
    }
    widget.workbench.updateFeatureStates(feat.id, states);
    if (oldVar.isNotEmpty && newVar.isNotEmpty && oldVar != newVar) {
      widget.workbench.propagateVariableRenameAcrossProject(oldVar, newVar);
    }
    if (newVar.isNotEmpty && valOnly.isNotEmpty) {
      widget.workbench.syncExportVarToVirtualFile(
        primaryAssetOrResPath: feat.sections['primary_asset'],
        varName: newVar,
        formattedValue: valOnly,
        featureId: feat.id,
      );
    }
    _rebuild();
  }

  void _retreatToPreviousStep(
    List<FeatureStateNode> states,
    int checkpointIndex,
    FeatureStateNode node,
    List<TaskHowToSubStep> unifiedSteps,
    int activeStepIdx,
    bool isPlaytestGate,
  ) {
    if (isPlaytestGate) {
      final lastIdx =
          unifiedSteps.isNotEmpty ? unifiedSteps.length - 1 : 0;
      _selectFlatStep(node.id, lastIdx);
      return;
    }
    if (activeStepIdx > 0) {
      _selectFlatStep(node.id, activeStepIdx - 1);
      return;
    }
    if (checkpointIndex > 0) {
      final prevCpIdx = checkpointIndex - 1;
      final prevCp = states[prevCpIdx];
      final prevSteps = TaskHowToBlueprint.resolveUnifiedSteps(
        checkpointNode: prevCp,
        engineHint: _engineHint,
        phase: widget.workbench.currentPhase,
      );
      final prevLastIdx = prevSteps.isNotEmpty ? prevSteps.length - 1 : 0;
      _rebuild(() {
        _manualCheckpointFocusIndex = prevCpIdx;
        _manualCheckpointFocusFeatureId = widget.workbench.selectedFeatureId;
        _playtestGateActiveCheckpoints.remove(prevCp.id);
        _selectedFlatStepIndexByCheckpoint[prevCp.id] = prevLastIdx;
      });
    }
  }

  void _browseToNextStep(
    List<FeatureStateNode> states,
    int checkpointIndex,
    FeatureStateNode node,
    List<TaskHowToSubStep> unifiedSteps,
    int activeStepIdx,
    bool isPlaytestGate,
  ) {
    if (!isPlaytestGate && activeStepIdx + 1 < unifiedSteps.length) {
      _selectFlatStep(node.id, activeStepIdx + 1);
      return;
    }
    if (!isPlaytestGate && unifiedSteps.isNotEmpty) {
      _openPlaytestGate(node.id);
      return;
    }
    if (checkpointIndex + 1 < states.length) {
      final nextCpIdx = checkpointIndex + 1;
      final nextCp = states[nextCpIdx];
      _rebuild(() {
        _manualCheckpointFocusIndex = nextCpIdx;
        _manualCheckpointFocusFeatureId = widget.workbench.selectedFeatureId;
        _playtestGateActiveCheckpoints.remove(nextCp.id);
        _selectedFlatStepIndexByCheckpoint[nextCp.id] = 0;
      });
    }
  }

  void _reorderBuildQueueStep(
    TierDocument feat,
    List<FeatureStateNode> states,
    int checkpointIndex,
    FeatureStateNode node,
    List<TaskHowToSubStep> unifiedSteps,
    int oldIdx,
    int newIdx,
  ) {
    if (newIdx < 0 || newIdx >= unifiedSteps.length || oldIdx == newIdx) {
      return;
    }
    _materializeUnifiedStepsIfNeeded(node, unifiedSteps);
    final ok = widget.workbench.reorderCheckpointStep(
      featureId: feat.id,
      states: states,
      checkpointIndex: checkpointIndex,
      oldIndex: oldIdx,
      newIndex: newIdx,
    );
    if (ok) {
      _selectFlatStep(node.id, newIdx);
    }
  }

  void _deleteBuildQueueStep(
    TierDocument feat,
    List<FeatureStateNode> states,
    int checkpointIndex,
    FeatureStateNode node,
    List<TaskHowToSubStep> unifiedSteps,
    int stepIdx,
  ) {
    if (unifiedSteps.length <= 1 ||
        stepIdx < 0 ||
        stepIdx >= unifiedSteps.length) {
      return;
    }
    _materializeUnifiedStepsIfNeeded(node, unifiedSteps);
    final ok = widget.workbench.removeCheckpointStep(
      featureId: feat.id,
      states: states,
      checkpointIndex: checkpointIndex,
      stepIndex: stepIdx,
    );
    if (ok) {
      final remainingCount = unifiedSteps.length - 1;
      final currentSelected = _selectedFlatStepIndexByCheckpoint[node.id] ?? 0;
      final nextSelected = (currentSelected >= remainingCount
              ? remainingCount - 1
              : (currentSelected > stepIdx
                  ? currentSelected - 1
                  : currentSelected))
          .clamp(0, remainingCount - 1);
      _selectFlatStep(node.id, nextSelected);
    }
  }

  ({String icon, String componentKey, String displayLabel})
      _resolveStepTargetComponent(
    TaskHowToSubStep subStep, {
    required String featTitle,
  }) {
    final verbPrefixRegex = RegExp(
      r'^(?:add|trace|calculate|clamp|trigger|respawn|set|bind|configure|create|implement|update|apply|check|verify|enforce|spawn|handle|process|execute|run)\b',
      caseSensitive: false,
    );

    final draft = widget.workbench.conceptDraft;
    final activeProjSections =
        widget.workbench.activeProject?.sections ?? const <String, String>{};
    final specCombined = [
      ...(draft?.gameSpec ?? const <String>[]),
      ...(draft?.techSpec ?? const <String>[]),
      draft?.goal ?? '',
      activeProjSections['game_spec'] ?? '',
      activeProjSections['tech_spec'] ?? '',
      _engineHint,
    ].join(' ').toLowerCase();
    final is2D = specCombined.contains('2d') ||
        specCombined.contains('pixel') ||
        specCombined.contains('sprite') ||
        specCombined.contains('side-scroller');

    final titleLower = subStep.shortTitle.toLowerCase();
    if (titleLower.contains('capsule') ||
        titleLower.contains('collider') ||
        titleLower.contains('collision hull') ||
        titleLower.contains('collision shape')) {
      return (
        icon: '📦',
        componentKey: is2D ? 'CollisionShape2D' : 'CollisionShape3D',
        displayLabel: is2D
            ? 'CollisionShape2D (CapsuleShape2D)'
            : 'CollisionShape3D (CapsuleShape3D)',
      );
    }

    final rawH = subStep.area1Hierarchy?.trim() ?? '';
    final isInputStep = titleLower.contains('input') ||
        titleLower.contains('mapping') ||
        subStep.stepPath.toLowerCase().contains('input map');
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
            .replaceAll(RegExp(r'^[├└│─\s•\-🎯📦⚙️📷🦴🧩📁⚡🗺]+'), '')
            .replaceAll('[ACTIVE]', '')
            .replaceAll('← SELECTED', '')
            .trim();
        if (clean.isEmpty ||
            clean.startsWith('[Root]') ||
            clean.toLowerCase().startsWith('class ')) {
          continue;
        }
        final cleanLower = clean.toLowerCase();
        if (cleanLower.contains('(level') || cleanLower.contains('(world)')) {
          continue;
        }
        if (!isInputStep &&
            (cleanLower.contains('input map') ||
                cleanLower.contains('input action'))) {
          continue;
        }
        if (!verbPrefixRegex.hasMatch(clean)) {
          final key = clean.split('(').first.trim();
          final icon = cleanLower.contains('camera')
              ? '📷'
              : (cleanLower.contains('box') ||
                      cleanLower.contains('capsule') ||
                      cleanLower.contains('trigger') ||
                      cleanLower.contains('collision') ||
                      cleanLower.contains('area') ||
                      cleanLower.contains('ray') ||
                      cleanLower.contains('floor') ||
                      cleanLower.contains('wall') ||
                      cleanLower.contains('volume')
                  ? '📦'
                  : (cleanLower.contains('mesh') ||
                          cleanLower.contains('sprite') ||
                          cleanLower.contains('visual') ||
                          cleanLower.contains('ramp')
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

    if (titleLower.contains('floor') ||
        titleLower.contains('arena') ||
        titleLower.contains('ground') ||
        titleLower.contains('geometry') ||
        titleLower.contains('blockout') ||
        titleLower.contains('slab') ||
        titleLower.contains('platform')) {
      return (
        icon: '📦',
        componentKey: 'ArenaFloor',
        displayLabel:
            is2D ? 'ArenaFloor (StaticBody2D)' : 'ArenaFloor (StaticBody3D)',
      );
    }

    final combinedText = [
      featTitle,
      subStep.shortTitle,
      subStep.instruction,
      subStep.codeFormula,
    ].join(' ').toLowerCase();

    if (combinedText.contains('camera') ||
        combinedText.contains('fov') ||
        combinedText.contains('spring')) {
      return (
        icon: '📷',
        componentKey: is2D ? 'Camera2D' : 'Camera3D',
        displayLabel: is2D ? 'Camera2D (Camera)' : 'Camera3D (Camera)',
      );
    }

    if (combinedText.contains('collision') ||
        combinedText.contains('trigger') ||
        combinedText.contains('overlap') ||
        combinedText.contains('raycast') ||
        combinedText.contains('hitbox') ||
        combinedText.contains('area')) {
      return (
        icon: '📦',
        componentKey: is2D ? 'Area2D' : 'Area3D',
        displayLabel: is2D
            ? 'CollisionTrigger (Area2D)'
            : 'CollisionTrigger (Area3D)',
      );
    }

    if (combinedText.contains('velocity') ||
        combinedText.contains('movement') ||
        combinedText.contains('dash') ||
        combinedText.contains('strafe') ||
        combinedText.contains('jump') ||
        combinedText.contains('impulse') ||
        combinedText.contains('character')) {
      return (
        icon: '⚙️',
        componentKey: 'CharacterBody',
        displayLabel: is2D
            ? 'PlayerBody (CharacterBody2D)'
            : 'PlayerBody (CharacterBody3D)',
      );
    }

    if (combinedText.contains('mesh') ||
        combinedText.contains('sprite') ||
        combinedText.contains('trail') ||
        combinedText.contains('hud') ||
        combinedText.contains('control')) {
      return (
        icon: '🎨',
        componentKey: is2D ? 'Sprite2D' : 'MeshInstance3D',
        displayLabel:
            is2D ? 'VisualNode (Sprite2D)' : 'VisualNode (MeshInstance3D)',
      );
    }

    final derivedAsset = TaskHowToBlueprint.deriveConcreteAssetName(
      featTitle,
    ).pascalName;
    final cleanKey =
        derivedAsset.isNotEmpty ? derivedAsset : 'GameplayNode';
    return (
      icon: '⚙️',
      componentKey: cleanKey,
      displayLabel: '$cleanKey (Node)',
    );
  }

  String _classifyFeatureArchetype(String title) {
    final lowerTitle = title.toLowerCase();
    if (RegExp(
      r'\b(?:hud|ui|widget|hotbar|menu|crosshair|selector|health\s*bar|inventory\s*bar|radar|minimap)\b',
    ).hasMatch(lowerTitle)) {
      return 'ui';
    } else if (RegExp(
      r'\b(?:player|character|pawn|strafe|locomotion|dash|sprint|jump|crouch|slide|grapple|parry|aim|camera|footstep)\b',
    ).hasMatch(lowerTitle)) {
      return 'character';
    } else if (RegExp(
      r'\b(?:arena|blockout|greybox|graybox|level|map|compound|sector|courtyard|room|world|stage|zone|biome|terrain)\b',
    ).hasMatch(lowerTitle)) {
      return 'level';
    }
    return 'actor';
  }

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
    required int activeStepIdx,
    required TaskHowToSubStep activeSubStep,
    required ({String icon, String componentKey, String displayLabel})
        activeTargetComp,
  }) {
    final draft = widget.workbench.conceptDraft;
    final activeProjSections =
        widget.workbench.activeProject?.sections ?? const <String, String>{};
    final specCombined = [
      ...(draft?.gameSpec ?? const <String>[]),
      ...(draft?.techSpec ?? const <String>[]),
      draft?.goal ?? '',
      activeProjSections['game_spec'] ?? '',
      activeProjSections['tech_spec'] ?? '',
      _engineHint,
    ].join(' ').toLowerCase();
    final is2D = specCombined.contains('2d') ||
        specCombined.contains('pixel') ||
        specCombined.contains('sprite') ||
        specCombined.contains('side-scroller');

    final archetype = _classifyFeatureArchetype(feat.title);
    final derivedNames = TaskHowToBlueprint.deriveConcreteAssetName(feat.title);
    final snakeName = derivedNames.snakeName.isNotEmpty
        ? derivedNames.snakeName
        : 'gameplay_feature';

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
        if (isPrevChar) hasPrecedingCharacter = true;
        if (archetype == 'character' && isPrevChar) {
          isFirstOfArchetype = false;
        }
      }
    }

    final isNewAssetOnTask =
        activeStepIdx == 0 && checkpointIndex == 0 && isFirstOfArchetype;
    final verifyCheckLower = activeSubStep.verifyResult.toLowerCase();
    final needsPlayerSpawnSetup =
        (archetype == 'level' || archetype == 'actor') &&
            (!hasPrecedingCharacter ||
                verifyCheckLower.contains('player') ||
                verifyCheckLower.contains('character') ||
                verifyCheckLower.contains('land') ||
                verifyCheckLower.contains('stand') ||
                verifyCheckLower.contains('spawn'));

    final assetIcon = archetype == 'level' ? '🗺' : '🎬';
    String assetName;
    String parentClassLabel;
    String folderPath;
    if (archetype == 'character') {
      assetName = 'player_character.tscn';
      parentClassLabel =
          is2D ? 'Root Node: CharacterBody2D' : 'Root Node: CharacterBody3D';
      folderPath = 'res://scenes/characters/';
    } else if (archetype == 'ui') {
      assetName = '${snakeName}_hud.tscn';
      parentClassLabel = 'Root Node: Control (CanvasLayer)';
      folderPath = 'res://scenes/ui/';
    } else if (archetype == 'level') {
      final cleanLevelSnake = snakeName.replaceAll(
        RegExp(r'_(?:blockout|greybox|graybox)$', caseSensitive: false),
        '',
      );
      final effectiveLevelSnake =
          cleanLevelSnake.isNotEmpty ? cleanLevelSnake : snakeName;
      assetName = '$effectiveLevelSnake.tscn';
      parentClassLabel = is2D
          ? 'Root Node: Node2D (Level Scene)'
          : 'Root Node: Node3D (Level Scene)';
      folderPath = 'res://scenes/levels/';
    } else {
      assetName = '$snakeName.tscn';
      parentClassLabel = is2D ? 'Root Node: Node2D' : 'Root Node: Node3D';
      folderPath = 'res://scenes/gameplay/';
    }

    final cpStatesForAsset = FeatureStateNode.getStatesForDocument(feat);
    final cpForAsset =
        (checkpointIndex >= 0 && checkpointIndex < cpStatesForAsset.length)
            ? cpStatesForAsset[checkpointIndex]
            : (cpStatesForAsset.isNotEmpty ? cpStatesForAsset.first : null);
    final rawCanonicalAsset = (feat.sections['primary_asset'] ??
            cpForAsset?.parameters['primarySharedScriptOrScene'] ??
            '')
        .trim();
    if (rawCanonicalAsset.isNotEmpty) {
      final lowerAsset = rawCanonicalAsset.toLowerCase();
      if (lowerAsset.startsWith('res://') ||
          lowerAsset.endsWith('.gd') ||
          lowerAsset.endsWith('.tscn') ||
          lowerAsset.endsWith('.tres')) {
        final slashIdx = rawCanonicalAsset.lastIndexOf('/');
        if (slashIdx != -1 && slashIdx < rawCanonicalAsset.length - 1) {
          folderPath = rawCanonicalAsset.substring(0, slashIdx + 1);
          assetName = rawCanonicalAsset.substring(slashIdx + 1);
        } else {
          assetName = rawCanonicalAsset;
        }
      }
    }

    final setupSteps = <({String label, String detail})>[];
    if (isNewAssetOnTask) {
      if (archetype == 'character') {
        final bodyNode = is2D ? 'CharacterBody2D' : 'CharacterBody3D';
        final colNode = is2D ? 'CollisionShape2D' : 'CollisionShape3D';
        final camNode = is2D ? 'Camera2D' : 'Camera3D';
        setupSteps.addAll([
          (label: 'Scene', detail: '+ $bodyNode root → Save $folderPath$assetName'),
          (label: 'Script', detail: '📜 Attach Script → player_character.gd'),
          (label: 'Nodes', detail: '+ Add $colNode (CapsuleShape) & $camNode'),
        ]);
      } else if (archetype == 'ui') {
        setupSteps.addAll([
          (label: 'Scene', detail: 'Control root → Save $folderPath$assetName'),
          (label: 'Script', detail: '📜 Attach Script → ${snakeName}_hud.gd'),
          (label: 'Control', detail: '+ Add ${activeTargetComp.displayLabel}'),
        ]);
      } else if (archetype == 'level') {
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
            detail: hasPrecedingCharacter
                ? 'Instantiate player_character.tscn ($bodyNode + gravity)'
                : 'Add Test Capsule (${is2D ? 'RigidBody2D + CollisionShape2D' : 'RigidBody3D + CollisionShape3D'})',
          ),
          (
            label: 'Spawn',
            detail: is2D
                ? 'Add Marker2D SpawnPoint at (0, -64) above floor'
                : 'Add Marker3D SpawnPoint at (0, 2, 0) above floor',
          ),
        ]);
      } else {
        final rootNode = is2D ? 'Node2D' : 'Node3D';
        setupSteps.addAll([
          (label: 'Scene', detail: 'Create $rootNode → Save $folderPath$assetName'),
          (label: 'Script', detail: '📜 Attach Script → $snakeName.gd'),
          (label: 'Child', detail: '+ Add ${activeTargetComp.displayLabel}'),
        ]);
      }
    }

    return (
      archetype: archetype,
      is2D: is2D,
      sec1Title: archetype == 'level'
          ? 'Scene Tree & Level Nodes'
          : 'Scene & Nodes (.tscn)',
      sec2Title: 'Property & Layer Sheet',
      sec3Title: archetype == 'level'
          ? 'Level Script (.gd) & World Setup'
          : 'GDScript (.gd) & Scene Setup',
      assetIcon: assetIcon,
      assetName: assetName,
      parentClassLabel: parentClassLabel,
      folderPath: folderPath,
      isNewAssetOnTask: isNewAssetOnTask,
      setupSteps: setupSteps,
      levelHookupTitle: needsPlayerSpawnSetup
          ? '🗺 MAIN SCENE & PLAYER SPAWN SETUP'
          : '🗺 MAIN SCENE SETUP',
      levelHookupSteps: const [],
    );
  }

  /// Infers the specific owning Godot node and Inspector category for a property row
  /// so CollisionShape, Camera, and CharacterBody properties are clearly attributed.
  ({String componentLabel, String categoryLabel, String propertyLabel})
      _inferOwningComponentForProperty({
    required String rawKey,
    required String defaultComponentKey,
    required bool is2D,
  }) {
    String defaultCatFor(String comp) {
      final lc = comp.toLowerCase();
      if (lc.contains('capsule') ||
          lc.contains('collider') ||
          lc.contains('collisionshape')) {
        return 'Shape: ${is2D ? 'CapsuleShape2D' : 'CapsuleShape3D'}';
      }
      if (lc.contains('camera') || lc.contains('springarm')) {
        return 'Node: Camera Transform';
      }
      if (lc.contains('movement') ||
          lc.contains('rigidbody') ||
          lc.contains('characterbody')) {
        return 'Script Variables (@export)';
      }
      return 'Inspector Properties';
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
        lower.contains('height')) {
      final comp = is2D ? 'CollisionShape2D' : 'CollisionShape3D';
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
      final comp = is2D ? 'Camera2D' : 'Camera3D';
      return (
        componentLabel: comp,
        categoryLabel: defaultCatFor(comp),
        propertyLabel: rawKey,
      );
    }
    if (lower.contains('walkspeed') ||
        lower.contains('move_speed') ||
        lower.contains('jump_velocity') ||
        lower.contains('air_control') ||
        lower.contains('gravity')) {
      const comp = 'CharacterBody';
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

  Color _dockStageAccent(GodotDockStage stage) {
    switch (stage) {
      case GodotDockStage.scene:
        return const Color(0xFF34D399);
      case GodotDockStage.inspector:
        return const Color(0xFF38BDF8);
      case GodotDockStage.code:
        return const Color(0xFFA78BFA);
      case GodotDockStage.wire:
        return const Color(0xFF22D3EE);
      case GodotDockStage.fix:
        return const Color(0xFFF59E0B);
      case GodotDockStage.gate:
        return const Color(0xFF10B981);
    }
  }

  Widget _buildWorkspaceModeToggle(FeatureStateNode node) {
    Widget tabBtn({
      required ValueKey<String> key,
      required String label,
      required bool active,
      required VoidCallback onTap,
    }) {
      return InkWell(
        key: key,
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1E293B) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: active ? weightBold : weightSemi,
              color: active ? const Color(0xFFF8FAFC) : textMuted,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF07090E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tabBtn(
            key: ValueKey('workspace_mode_runbook_btn_${node.id}'),
            label: 'Runbook',
            active: !_isCodeFileWorkspaceMode,
            onTap: () => _rebuild(() {
              _isCodeFileWorkspaceMode = false;
            }),
          ),
          tabBtn(
            key: ValueKey('workspace_mode_code_file_btn_${node.id}'),
            label: 'Code File',
            active: _isCodeFileWorkspaceMode,
            onTap: () => _rebuild(() {
              _isCodeFileWorkspaceMode = true;
            }),
          ),
        ],
      ),
    );
  }

  void _triggerPrimaryDoneAction({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required FeatureStateNode node,
    required List<TaskHowToSubStep> unifiedSteps,
    required int activeStepIdx,
    required bool isPlaytestGate,
  }) {
    if (isPlaytestGate) {
      _passCheckpointPlaytestAndAdvance(feat, states, node);
      return;
    }
    final activeSub = unifiedSteps.isNotEmpty
        ? unifiedSteps[activeStepIdx.clamp(0, unifiedSteps.length - 1)]
        : null;
    final allBuildDone = unifiedSteps.isNotEmpty &&
        unifiedSteps.every((s) => s.subtask.completed);
    if (activeSub == null) {
      _passCheckpointPlaytestAndAdvance(feat, states, node);
      return;
    }
    if (activeSub.subtask.completed) {
      if (allBuildDone) {
        _openPlaytestGate(node.id);
      } else {
        _jumpToNextIncompleteStep(feat, states, node);
      }
      return;
    }
    _completeCurrentFlatStepAndAdvance(
      feat,
      states,
      node,
      unifiedSteps,
      activeStepIdx,
    );
  }

  Widget _buildUnifiedDoneButton({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required FeatureStateNode node,
    required List<TaskHowToSubStep> unifiedSteps,
    required int activeStepIdx,
    required bool isPlaytestGate,
    required bool isHalfScreenOverlayMode,
  }) {
    final activeSub = unifiedSteps.isNotEmpty
        ? unifiedSteps[activeStepIdx.clamp(0, unifiedSteps.length - 1)]
        : null;
    final allBuildDone = unifiedSteps.isNotEmpty &&
        unifiedSteps.every((s) => s.subtask.completed);
    final bool isStepCompleted = activeSub != null && activeSub.subtask.completed;
    final bool isVerifiedDoneState =
        isPlaytestGate ? node.isPlaytestPassed : isStepCompleted;

    final String label = isPlaytestGate
        ? (node.isPlaytestPassed
            ? '✓ Verified'
            : (isHalfScreenOverlayMode
                ? '✓ Pass F6 Gate →'
                : '✓ Pass Playtest & Next →'))
        : (isStepCompleted
            ? (allBuildDone ? 'Open F6 Gate →' : 'Next Unfinished →')
            : (isHalfScreenOverlayMode ? 'Done & Next →' : 'Done & Next →'));

    return InkWell(
      key: ValueKey('one_click_complete_next_btn_${node.id}'),
      onTap: () => _triggerPrimaryDoneAction(
        feat: feat,
        states: states,
        node: node,
        unifiedSteps: unifiedSteps,
        activeStepIdx: activeStepIdx,
        isPlaytestGate: isPlaytestGate,
      ),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isHalfScreenOverlayMode ? 9 : 12,
          vertical: isHalfScreenOverlayMode ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: isVerifiedDoneState
              ? const Color(0xFF10B981).withValues(alpha: 0.18)
              : const Color(0xFF10B981),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isVerifiedDoneState
                ? const Color(0xFF10B981).withValues(alpha: 0.45)
                : const Color(0xFF34D399),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isHalfScreenOverlayMode ? fontMicro : fontBody,
            fontWeight: weightBold,
            color: isVerifiedDoneState
                ? const Color(0xFF6EE7B7)
                : const Color(0xFF042F2E),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureActionsMenu({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required FeatureStateNode node,
    required int activeStepIdx,
    required bool isHalfScreen,
  }) {
    return PopupMenuButton<String>(
      key: isHalfScreen
          ? ValueKey('halfscreen_feature_actions_menu_btn_${feat.id}')
          : ValueKey('desktop_feature_actions_menu_btn_${feat.id}'),
      tooltip: 'Feature actions',
      color: bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderBright),
      ),
      onSelected: (action) {
        if (action == 'copy_ai_prompt') {
          _copyActiveFeaturePrompt(feat);
        } else if (action == 'tailor_step') {
          _promptTailorHowToDialog(feat, states, checkpointIndex, activeStepIdx);
        } else if (action == 'log_issue') {
          _rebuild(() {
            _inlineBugDrawerNodeId =
                _inlineBugDrawerNodeId == node.id ? null : node.id;
            _inlineBugInputCtrl.clear();
          });
        } else if (action == 'godot_contract') {
          showGodotContractDialog(context, widget.workbench);
        } else if (action == 'rename_feature') {
          _startStage2InlineEdit('rename_header_feat_${feat.id}', feat.title);
        } else if (action == 'add_step') {
          _startStage2InlineEdit('workspace_add_task_${node.id}', '');
        } else if (action == 'edit_tuning') {
          _showEditCheckpointTuningAndGuardsDialog(feat, states, node);
        } else if (action == 'feature_inbox') {
          _showFeatureInboxModal(context, preferredBeatId: feat.parentId);
        } else if (action == 'toggle_complete_all') {
          final steps = TaskHowToBlueprint.resolveUnifiedSteps(
            checkpointNode: node,
            engineHint: _engineHint,
            phase: widget.workbench.currentPhase,
          );
          _materializeUnifiedStepsIfNeeded(node, steps);
          if (node.isCompleted) {
            for (final task in node.checklist) {
              task.completed = false;
              for (final child in task.children) {
                child.completed = false;
              }
            }
            node.isPlaytestPassed = false;
            widget.workbench.updateFeatureStates(feat.id, states);
            _rebuild(() {});
          } else {
            _completeAllCheckpointTasks(node);
            _rebuild(() {
              _manualCheckpointFocusIndex = checkpointIndex;
              _manualCheckpointFocusFeatureId = feat.id;
              _playtestGateActiveCheckpoints.add(node.id);
              _awaitingPlaytestVerification.add(node.id);
            });
            widget.workbench.updateFeatureStates(feat.id, states);
          }
        } else if (action == 'archive_pivot') {
          widget.workbench.toggleSupersedeFeature(
            feat.id,
            pivotReason: 'Archived from Feature Header',
          );
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          value: 'add_step',
          height: 34,
          child: Text(
            '+ Add Step',
            style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
          ),
        ),
        if (isHalfScreen) ...[
          PopupMenuItem<String>(
            value: 'tailor_step',
            height: 34,
            child: Text(
              '✦ Tailor active step',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFFA5B4FC),
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
                color: const Color(0xFFFBBF24),
              ),
            ),
          ),
          PopupMenuItem<String>(
            value: 'godot_contract',
            height: 34,
            child: Text(
              '⚙ Project contract',
              style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
            ),
          ),
          const PopupMenuDivider(height: 8),
        ],
        PopupMenuItem<String>(
          value: 'copy_ai_prompt',
          height: 34,
          child: Text(
            '⧉ Copy AI prompt',
            style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
          ),
        ),
        if (isHalfScreen)
          PopupMenuItem<String>(
            value: 'rename_feature',
            height: 34,
            child: Text(
              '✎ Rename feature',
              style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
            ),
          ),
        PopupMenuItem<String>(
          value: 'edit_tuning',
          height: 34,
          child: Text(
            'Edit tuning & guards',
            style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
          ),
        ),
        PopupMenuItem<String>(
          value: 'feature_inbox',
          height: 34,
          child: Text(
            'Feature inbox',
            style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
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
              color: node.isCompleted ? textSecondary : accentEmerald,
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'archive_pivot',
          height: 34,
          child: Text(
            'Archive / pivot',
            style: GoogleFonts.inter(fontSize: 12.5, color: accentCrimson),
          ),
        ),
      ],
      child: Container(
        width: isHalfScreen ? 24 : 26,
        height: isHalfScreen ? 24 : 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isHalfScreen ? bgSurface : const Color(0xFF181E2C),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isHalfScreen ? borderBright : const Color(0xFF262E40),
          ),
        ),
        child: Text(
          '⋯',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildSplitScreenFloatingHeader({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int index,
    required FeatureStateNode node,
    required List<TaskHowToSubStep> unifiedSteps,
    required int activeStepIdx,
    required bool isPlaytestGate,
    required bool canGoPrev,
    required bool canGoNext,
    required bool isFeatureBeingBuiltInLiveMode,
    required bool isSynthesizingFeatureNow,
    required String epicShortCode,
    required String featShortTitle,
    required String featureGoalText,
    required Widget doneBtn,
    required Widget featureActionsMenu,
  }) {
    final activeSub = unifiedSteps.isNotEmpty
        ? unifiedSteps[activeStepIdx.clamp(0, unifiedSteps.length - 1)]
        : null;

    final Widget stepPicker = unifiedSteps.isNotEmpty
        ? PopupMenuButton<int>(
            key: ValueKey('step_dropdown_${node.id}'),
            tooltip: 'Switch Step or F6 Playtest Gate',
            color: bgSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: borderBright),
            ),
            onSelected: (selectedVal) {
              if (selectedVal == -1) {
                _openPlaytestGate(node.id);
              } else {
                _selectFlatStep(node.id, selectedVal);
              }
            },
            itemBuilder: (context) => [
              for (int sIdx = 0; sIdx < unifiedSteps.length; sIdx++)
                PopupMenuItem<int>(
                  value: sIdx,
                  height: 36,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: _dockStageAccent(
                            unifiedSteps[sIdx].resolvedDockStage,
                          ).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          unifiedSteps[sIdx].resolvedDockStage.badge,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 8.5,
                            fontWeight: weightBold,
                            color: _dockStageAccent(
                              unifiedSteps[sIdx].resolvedDockStage,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${(sIdx + 1).toString().padLeft(2, '0')} · ${unifiedSteps[sIdx].shortTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: fontBody,
                            fontWeight: !isPlaytestGate && sIdx == activeStepIdx
                                ? weightBold
                                : weightRegular,
                            color: !isPlaytestGate && sIdx == activeStepIdx
                                ? textPrimary
                                : (unifiedSteps[sIdx].subtask.completed
                                    ? textMuted
                                    : textSecondary),
                          ),
                        ),
                      ),
                      if (unifiedSteps[sIdx].subtask.completed) ...[
                        const SizedBox(width: 8),
                        Text(
                          '✓',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: fontMicro,
                            fontWeight: weightBold,
                            color: accentEmerald,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const PopupMenuDivider(height: 8),
              PopupMenuItem<int>(
                value: -1,
                height: 36,
                child: Row(
                  children: [
                    Text(
                      '▶ F6 · Playtest Gate',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: fontMicro,
                        fontWeight: weightBold,
                        color: isPlaytestGate ? accentEmerald : textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (node.isPlaytestPassed)
                      Text(
                        '✓',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: fontMicro,
                          fontWeight: weightBold,
                          color: accentEmerald,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: bgSurface,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: borderBright),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isPlaytestGate
                        ? 'F6 Gate'
                        : 'Step ${activeStepIdx + 1}/${unifiedSteps.length}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: fontMicro,
                      fontWeight: weightSemi,
                      color: isPlaytestGate
                          ? accentEmerald
                          : ((activeSub?.subtask.completed ?? false)
                              ? accentEmerald
                              : accentCyan),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 13,
                    color: textMuted,
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: bgRecessed,
        border: Border(bottom: BorderSide(color: borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: InkWell(
                  key: ValueKey('halfscreen_outliner_trigger_${node.id}'),
                  onTap: () {
                    _rebuild(() {
                      _isHalfScreenOutlinerOpen = !_isHalfScreenOutlinerOpen;
                    });
                  },
                  borderRadius: BorderRadius.circular(5),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: _isHalfScreenOutlinerOpen
                                  ? accentEmerald
                                  : borderBright,
                            ),
                          ),
                          child: Text(
                            '☰',
                            style: GoogleFonts.inter(
                              fontSize: fontBody,
                              fontWeight: weightSemi,
                              color: _isHalfScreenOutlinerOpen
                                  ? textPrimary
                                  : textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: GoogleFonts.inter(
                                fontSize: fontBody,
                                fontWeight: weightBold,
                                color: textPrimary,
                              ),
                              children: [
                                TextSpan(
                                  text: '$epicShortCode › ',
                                  style: GoogleFonts.inter(
                                    fontSize: fontMicro,
                                    fontWeight: weightSemi,
                                    color: textMuted,
                                  ),
                                ),
                                TextSpan(text: featShortTitle),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
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
                  if (isFeatureBeingBuiltInLiveMode)
                    Text(
                      isSynthesizingFeatureNow ? 'Building…' : 'Waiting',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSynthesizingFeatureNow
                            ? const Color(0xFFFBBF24)
                            : textMuted,
                      ),
                    )
                  else ...[
                    stepPicker,
                    const SizedBox(width: 2),
                    InkWell(
                      onTap: canGoPrev
                          ? () => _retreatToPreviousStep(
                                states,
                                index,
                                node,
                                unifiedSteps,
                                activeStepIdx,
                                isPlaytestGate,
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
                            color: canGoPrev
                                ? textSecondary
                                : textMuted.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: canGoNext
                          ? () => _browseToNextStep(
                                states,
                                index,
                                node,
                                unifiedSteps,
                                activeStepIdx,
                                isPlaytestGate,
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
                            color: canGoNext
                                ? textSecondary
                                : textMuted.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    doneBtn,
                    const SizedBox(width: 4),
                    featureActionsMenu,
                  ],
                ],
              ),
            ],
          ),
          if (_activeStage2InlineEditKey == 'rename_header_feat_${feat.id}')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _buildStage2InlineEditor(
                editKey: 'rename_header_feat_${feat.id}',
                inputKey: const ValueKey('workbench_rename_live_feature_input'),
                saveBtnKey: const ValueKey(
                  'confirm_workbench_rename_live_feature_btn',
                ),
                hintText: 'Feature title...',
                onSave: (val) =>
                    widget.workbench.renameLiveFeature(feat.id, val),
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
                  for (int cpIdx = 0; cpIdx < states.length; cpIdx++)
                    InkWell(
                      key: ValueKey('halfscreen_cp_${feat.id}_$cpIdx'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        _rebuild(() {
                          _manualCheckpointFocusIndex = cpIdx;
                          _manualCheckpointFocusFeatureId = feat.id;
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
                          color: accentEmerald.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: accentEmerald.withValues(alpha: 0.35),
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
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  key: ValueKey('task_sheet_feature_goal_${node.id}'),
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
              ),
              const SizedBox(width: 8),
              _buildWorkspaceModeToggle(node),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSlimFeatureHeader({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int index,
    required FeatureStateNode node,
    required List<TaskHowToSubStep> unifiedSteps,
    required int activeStepIdx,
    required bool isPlaytestGate,
    required bool canGoPrev,
    required bool canGoNext,
    required bool isSynthesizingFeatureNow,
    required String epicShortCode,
    required String featShortTitle,
    required String featureGoalText,
    required ({
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
    }) assetSpec,
    required Widget doneBtn,
    required Widget featureActionsMenu,
  }) {
    final bool isRenamingHeaderFeat =
        _activeStage2InlineEditKey == 'rename_header_feat_${feat.id}';
    final bool isDrawerOpen = _inlineBugDrawerNodeId == node.id;
    final activeSub = unifiedSteps.isNotEmpty
        ? unifiedSteps[activeStepIdx.clamp(0, unifiedSteps.length - 1)]
        : null;
    final bool isFixStepActive =
        activeSub != null && activeSub.resolvedDockStage == GodotDockStage.fix;

    Widget actionPill({
      required ValueKey<String> key,
      required VoidCallback? onTap,
      required String label,
      required Color fgColor,
      Color bgColor = const Color(0xFF181E2C),
      Color borderColor = const Color(0xFF262E40),
    }) {
      return InkWell(
        key: key,
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
          decoration: BoxDecoration(
            color: onTap == null ? Colors.transparent : bgColor,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: onTap == null ? const Color(0x14FFFFFF) : borderColor,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: fontMicro,
              fontWeight: weightSemi,
              color: onTap == null ? const Color(0xFF475569) : fgColor,
            ),
          ),
        ),
      );
    }

    return Container(
      key: ValueKey('unified_header_${node.id}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0E131D),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Breadcrumb + CP Switcher + Asset/Contract + Mode Toggle
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isRenamingHeaderFeat)
                    SizedBox(
                      width: 220,
                      child: _buildStage2InlineEditor(
                        editKey: 'rename_header_feat_${feat.id}',
                        inputKey: const ValueKey(
                          'workbench_rename_live_feature_input',
                        ),
                        saveBtnKey: const ValueKey(
                          'confirm_workbench_rename_live_feature_btn',
                        ),
                        hintText: 'Feature title...',
                        onSave: (val) =>
                            widget.workbench.renameLiveFeature(feat.id, val),
                      ),
                    )
                  else
                    InkWell(
                      key: ValueKey('workbench_rename_feature_btn_${feat.id}'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _startStage2InlineEdit(
                        'rename_header_feat_${feat.id}',
                        feat.title,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 1,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$epicShortCode › ',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: fontMicro,
                                fontWeight: weightSemi,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: Text(
                                featShortTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: fontBody,
                                  fontWeight: weightBold,
                                  color: const Color(0xFFF8FAFC),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '✎',
                              style: GoogleFonts.inter(
                                fontSize: fontMicro,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07090E),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (int cpIdx = 0; cpIdx < states.length; cpIdx++) ...[
                          if (cpIdx > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Text(
                                '→',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ),
                          InkWell(
                            key: ValueKey('outline_cp_${feat.id}_$cpIdx'),
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              _rebuild(() {
                                _manualCheckpointFocusIndex = cpIdx;
                                _manualCheckpointFocusFeatureId = feat.id;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cpIdx == index
                                    ? const Color(0xFF38BDF8)
                                        .withValues(alpha: 0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: cpIdx == index
                                      ? const Color(0xFF38BDF8)
                                          .withValues(alpha: 0.42)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                'CP${cpIdx + 1} · ${states[cpIdx].releaseVersion}${states[cpIdx].isCompleted ? ' ✓' : ''}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: cpIdx == index
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: cpIdx == index
                                      ? const Color(0xFF7DD3FC)
                                      : (states[cpIdx].isCompleted
                                          ? const Color(0xFF6EE7B7)
                                          : const Color(0xFF94A3B8)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Tooltip(
                    message:
                        'Open generated GDScript & Starter .tscn in Code File view',
                    child: InkWell(
                      key: ValueKey('desktop_shared_asset_badge_${node.id}'),
                      borderRadius: BorderRadius.circular(5),
                      onTap: () => _rebuild(() {
                        _isCodeFileWorkspaceMode = true;
                        _isShowingStarterTscnInCodeMode = false;
                        _selectedCodeFileResPath = widget.workbench
                            .extractPrimaryScriptResPath(
                          feat.sections['primary_asset'],
                        );
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF07090E),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0xFF283854)),
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${assetSpec.assetIcon} ${assetSpec.assetName}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFCBD5E1),
                              ),
                            ),
                            if (assetSpec.parentClassLabel.isNotEmpty ||
                                assetSpec.folderPath.isNotEmpty)
                              Text(
                                '${assetSpec.parentClassLabel}${assetSpec.parentClassLabel.isNotEmpty && assetSpec.folderPath.isNotEmpty ? ' · ' : ''}${assetSpec.folderPath}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    key: ValueKey('godot_contract_chip_${node.id}'),
                    borderRadius: BorderRadius.circular(5),
                    onTap: () =>
                        showGodotContractDialog(context, widget.workbench),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07090E),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Text(
                        '⚙ Contract',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
                  if (isFixStepActive && isSynthesizingFeatureNow)
                    Container(
                      key: ValueKey('diagnosing_fix_badge_${node.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.42),
                        ),
                      ),
                      child: Text(
                        '✦ Diagnosing Root-Cause Fix…',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFCD34D),
                        ),
                      ),
                    ),
                  if (isSynthesizingFeatureNow)
                    Container(
                      key: ValueKey('synthesizing_steps_badge_${feat.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        '✦ Building Steps...',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF7DD3FC),
                        ),
                      ),
                    ),
                ],
              ),
              _buildWorkspaceModeToggle(node),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Slim 1-Line Feature Goal + Primary Navigation & Action Controls
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  key: ValueKey('task_sheet_feature_goal_${node.id}'),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'WHAT  ',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: weightBold,
                            letterSpacing: 0.5,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        TextSpan(
                          text: featureGoalText,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFCBD5E1),
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  actionPill(
                    key: ValueKey('engine_dock_prev_step_${node.id}'),
                    onTap: canGoPrev
                        ? () => _retreatToPreviousStep(
                              states,
                              index,
                              node,
                              unifiedSteps,
                              activeStepIdx,
                              isPlaytestGate,
                            )
                        : null,
                    label: '‹',
                    fgColor: const Color(0xFFCBD5E1),
                  ),
                  actionPill(
                    key: ValueKey('engine_dock_next_step_${node.id}'),
                    onTap: canGoNext
                        ? () => _browseToNextStep(
                              states,
                              index,
                              node,
                              unifiedSteps,
                              activeStepIdx,
                              isPlaytestGate,
                            )
                        : null,
                    label: '›',
                    fgColor: const Color(0xFFCBD5E1),
                  ),
                  if (!isPlaytestGate && unifiedSteps.isNotEmpty)
                    actionPill(
                      key: ValueKey('tailor_howto_btn_${node.id}_$activeStepIdx'),
                      onTap: () => _promptTailorHowToDialog(
                        feat,
                        states,
                        index,
                        activeStepIdx,
                      ),
                      label: '✦ Tailor',
                      fgColor: const Color(0xFFA5B4FC),
                    ),
                  actionPill(
                    key: ValueKey('feature_gate_log_bug_btn_${node.id}'),
                    onTap: () {
                      _rebuild(() {
                        if (isDrawerOpen) {
                          _inlineBugDrawerNodeId = null;
                        } else {
                          _inlineBugDrawerNodeId = node.id;
                          _inlineBugInputCtrl.clear();
                        }
                      });
                    },
                    label: '⚑ Issue',
                    fgColor: isDrawerOpen
                        ? const Color(0xFFFCD34D)
                        : const Color(0xFFFBBF24),
                    bgColor: isDrawerOpen
                        ? const Color(0xFFFBBF24).withValues(alpha: 0.14)
                        : const Color(0xFF181E2C),
                    borderColor: isDrawerOpen
                        ? const Color(0xFFFBBF24).withValues(alpha: 0.45)
                        : const Color(0xFF262E40),
                  ),
                  doneBtn,
                  featureActionsMenu,
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Persistent left **`BUILD QUEUE`** rail inside Desktop Workspace:
  /// Flat dock-ordered step rows with checkboxes, `[SCENE]`/`[INSP]`/`[CODE]`/`[WIRE]`/`[FIX]` tags,
  /// `▲`/`▼` reorder, `+ Add Step`, and pinned `F6 · PLAYTEST GATE`.
  Widget _buildBuildQueueRail({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int index,
    required FeatureStateNode node,
    required List<TaskHowToSubStep> unifiedSteps,
    required int activeStepIdx,
    required bool isPlaytestGate,
    required List<String> edgeItems,
    bool fillHeight = false,
  }) {
    final doneCount = unifiedSteps.where((s) => s.subtask.completed).length;

    final stepsList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int sIdx = 0; sIdx < unifiedSteps.length; sIdx++)
          Builder(
            builder: (context) {
              final step = unifiedSteps[sIdx];
              final dock = step.resolvedDockStage;
              final dockColor = _dockStageAccent(dock);
              final isSelected = !isPlaytestGate && sIdx == activeStepIdx;
              final isDone = step.subtask.completed;
              final title = step.shortTitle.trim().isNotEmpty
                  ? step.shortTitle.trim()
                  : step.subtask.text;

              return InkWell(
                key: ValueKey('build_queue_step_${node.id}_$sIdx'),
                onTap: () => _selectFlatStep(node.id, sIdx),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF131C2D)
                        : Colors.transparent,
                    border: Border(
                      left: BorderSide(
                        color: isSelected ? dockColor : Colors.transparent,
                        width: 2.5,
                      ),
                      bottom: const BorderSide(color: Color(0xFF131A29)),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        key: ValueKey('build_queue_check_${node.id}_$sIdx'),
                        onTap: () => _toggleHowToSubStepCompletion(
                          feat,
                          states,
                          node,
                          sIdx,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          width: 15,
                          height: 15,
                          margin: const EdgeInsets.only(top: 2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isDone
                                ? accentEmerald
                                : const Color(0xFF07090E),
                            borderRadius: BorderRadius.circular(3.5),
                            border: Border.all(
                              color: isDone
                                  ? accentEmerald
                                  : (isSelected
                                      ? const Color(0xFF38BDF8)
                                      : const Color(0xFF334155)),
                            ),
                          ),
                          child: Text(
                            isDone ? '✓' : '',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              fontWeight: weightBold,
                              color: const Color(0xFF05101A),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  (sIdx + 1).toString().padLeft(2, '0'),
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9,
                                    fontWeight: weightBold,
                                    color: isSelected
                                        ? const Color(0xFF7DD3FC)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: dockColor.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    dock.badge,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 8,
                                      fontWeight: weightBold,
                                      color: dockColor,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  step.etaLabel,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 8.5,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: isSelected ? weightBold : weightSemi,
                                color: isDone
                                    ? const Color(0xFF64748B)
                                    : (isSelected
                                        ? const Color(0xFFF8FAFC)
                                        : const Color(0xFFCBD5E1)),
                                decoration: isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                key: ValueKey(
                                  'build_queue_move_up_${node.id}_$sIdx',
                                ),
                                onTap: sIdx > 0
                                    ? () => _reorderBuildQueueStep(
                                          feat,
                                          states,
                                          index,
                                          node,
                                          unifiedSteps,
                                          sIdx,
                                          sIdx - 1,
                                        )
                                    : null,
                                child: Icon(
                                  Icons.keyboard_arrow_up_rounded,
                                  size: 14,
                                  color: sIdx > 0
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF283244),
                                ),
                              ),
                              InkWell(
                                key: ValueKey(
                                  'build_queue_move_down_${node.id}_$sIdx',
                                ),
                                onTap: sIdx + 1 < unifiedSteps.length
                                    ? () => _reorderBuildQueueStep(
                                          feat,
                                          states,
                                          index,
                                          node,
                                          unifiedSteps,
                                          sIdx,
                                          sIdx + 1,
                                        )
                                    : null,
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 14,
                                  color: sIdx + 1 < unifiedSteps.length
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF283244),
                                ),
                              ),
                            ],
                          ),
                          if (unifiedSteps.length > 1) ...[
                            const SizedBox(width: 2),
                            Tooltip(
                              message: 'Remove step',
                              child: InkWell(
                                key: ValueKey(
                                  'build_queue_delete_step_${node.id}_$sIdx',
                                ),
                                borderRadius: BorderRadius.circular(3),
                                onTap: () => _deleteBuildQueueStep(
                                  feat,
                                  states,
                                  index,
                                  node,
                                  unifiedSteps,
                                  sIdx,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 12,
                                    color: Color(0xFF64748B),
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
              );
            },
          ),
      ],
    );

    return Container(
      key: ValueKey('build_queue_rail_${node.id}'),
      width: 274,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0D14),
        border: Border(right: BorderSide(color: Color(0xFF182032))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF182032))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'BUILD QUEUE',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: weightBold,
                            letterSpacing: 0.7,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141B29),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF232E45)),
                        ),
                        child: Text(
                          '$doneCount/${unifiedSteps.length}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: weightBold,
                            color: doneCount == unifiedSteps.length &&
                                    unifiedSteps.isNotEmpty
                                ? accentEmerald
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  key: ValueKey('build_queue_add_step_btn_${node.id}'),
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _startStage2InlineEdit(
                    'workspace_add_task_${node.id}',
                    '',
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B2A),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF26334D)),
                    ),
                    child: Text(
                      '+ Add Step',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: weightSemi,
                        color: const Color(0xFF7DD3FC),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (fillHeight)
            Expanded(
              child: SingleChildScrollView(child: stepsList),
            )
          else
            stepsList,

          // Pinned F6 Playtest Gate at bottom of Build Queue
          InkWell(
            key: ValueKey('build_queue_playtest_gate_${node.id}'),
            onTap: () => _openPlaytestGate(node.id),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                color: isPlaytestGate
                    ? const Color(0xFF0A241C)
                    : const Color(0xFF091114),
                border: Border(
                  left: BorderSide(
                    color: isPlaytestGate
                        ? const Color(0xFF34D399)
                        : Colors.transparent,
                    width: 2.5,
                  ),
                  top: const BorderSide(color: Color(0xFF1A2538)),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '▶ F6',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: weightBold,
                      color: const Color(0xFF34D399),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Playtest Gate',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: isPlaytestGate ? weightBold : weightSemi,
                        color: isPlaytestGate
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                  if (node.isPlaytestPassed)
                    Text(
                      '✓',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: weightBold,
                        color: accentEmerald,
                      ),
                    )
                  else if (edgeItems.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D160B),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color:
                              const Color(0xFFF59E0B).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        '${edgeItems.length}G',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8.5,
                          fontWeight: weightBold,
                          color: const Color(0xFFFCD34D),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Inline `Code File` Workspace View: shows cumulative Cloud `.gd` scripts + starter `.tscn`,
  /// live Plan B disk diff status, `Copy Full`, `Review Diff -> Write`, and disk `Undo`.
  Widget _buildCodeFileWorkspaceView({
    required TierDocument feat,
    required FeatureStateNode node,
    required List<TaskHowToSubStep> unifiedSteps,
    required ({String icon, String componentKey, String displayLabel})
        activeTargetComp,
    required ({
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
    }) assetSpec,
    required List<String> tuningItems,
    required List<String> edgeItems,
  }) {
    final files = widget.workbench.activeProjectGodotFiles;
    final defaultRes = _resolveEffectiveResPathForStep(
      feat: feat,
      node: node,
      subStep: unifiedSteps.isNotEmpty
          ? unifiedSteps.first
          : TaskHowToSubStep(
              subtask: Subtask(id: 'tmp', text: feat.title),
              stepNumberLabel: '01',
              instruction: '',
              codeFormula: '',
            ),
    );

    final featureResPaths = <String>{
      if (defaultRes.endsWith('.gd') || defaultRes.endsWith('.tres'))
        GodotVirtualFile.normalizeResPath(defaultRes),
    };
    final primaryScript = widget.workbench.extractPrimaryScriptResPath(
      feat.sections['primary_asset'] ??
          node.parameters['primarySharedScriptOrScene'],
    );
    if (primaryScript != null && primaryScript.isNotEmpty) {
      featureResPaths.add(GodotVirtualFile.normalizeResPath(primaryScript));
    }
    for (final st in unifiedSteps) {
      final extracted =
          widget.workbench.extractPrimaryScriptResPath(st.stepPath);
      if (extracted != null && extracted.isNotEmpty) {
        featureResPaths.add(GodotVirtualFile.normalizeResPath(extracted));
      }
    }
    final slugTokens = feat.title
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length >= 3)
        .toList();
    final featureFiles = <GodotVirtualFile>[];
    final otherFiles = <GodotVirtualFile>[];
    for (final vf in files) {
      final norm = GodotVirtualFile.normalizeResPath(vf.resPath);
      final matchesFeature = featureResPaths.contains(norm) ||
          slugTokens.any(norm.toLowerCase().contains);
      if (matchesFeature) {
        featureFiles.add(vf);
      } else {
        otherFiles.add(vf);
      }
    }

    GodotVirtualFile? selectedFile;
    if (files.isNotEmpty) {
      if (_selectedCodeFileResPath != null) {
        final match = files.where((f) => f.resPath == _selectedCodeFileResPath);
        if (match.isNotEmpty) selectedFile = match.first;
      }
      if (selectedFile == null && featureFiles.isNotEmpty) {
        selectedFile = featureFiles.firstWhere(
          (f) => f.resPath == defaultRes,
          orElse: () => featureFiles.first,
        );
      }
      selectedFile ??= files.firstWhere(
        (f) => f.resPath == defaultRes,
        orElse: () => files.first,
      );
    }

    final displayedFiles = (_showAllProjectFilesInCodeMode ||
            featureFiles.isEmpty ||
            (selectedFile != null && !featureFiles.contains(selectedFile)))
        ? <GodotVirtualFile>[...featureFiles, ...otherFiles]
        : featureFiles;

    final cleanRoot = assetSpec.assetName.replaceAll(RegExp(r'\.(tscn|gd)$'), '');
    final sceneSteps = unifiedSteps
        .where((s) => s.resolvedDockStage == GodotDockStage.scene)
        .toList();
    final sceneLines = sceneSteps.isNotEmpty
        ? _synthesizeSceneTreeLines(
            sceneSteps.first,
            activeTargetComp: activeTargetComp,
            assetName: assetSpec.assetName,
          )
        : const <String>[];
    final scriptForTscn = selectedFile?.resPath ??
        (defaultRes.endsWith('.gd') ? defaultRes : null);
    final starterTscnText = _buildFeatureStarterTscnText(
      assetName: assetSpec.assetName,
      parentClassLabel: assetSpec.parentClassLabel,
      is2D: assetSpec.is2D,
      sceneTreeLines: sceneLines,
      scriptResPath: scriptForTscn,
    );

    final bool showingTscn =
        _isShowingStarterTscnInCodeMode || selectedFile == null;
    final bool isUnsavedScaffoldFallback = selectedFile == null;
    final String activePath = showingTscn
        ? '${assetSpec.folderPath}${assetSpec.assetName.endsWith('.tscn') ? assetSpec.assetName : '$cleanRoot.tscn'}'
        : selectedFile.resPath;
    final String activeContent =
        showingTscn ? starterTscnText : selectedFile.content;
    final bool isEditingActiveFile =
        !showingTscn && _editingCodeFileResPath == selectedFile.resPath;
    final lines = activeContent.split('\n');

    Widget toolbarBtn({
      required ValueKey<String> key,
      required String label,
      required VoidCallback onTap,
      Color fgColor = const Color(0xFFCBD5E1),
      Color bgColor = const Color(0xFF181E2C),
      Color borderColor = const Color(0xFF283854),
      bool bold = false,
    }) {
      return InkWell(
        key: key,
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9.5,
              fontWeight: bold ? weightBold : weightSemi,
              color: fgColor,
            ),
          ),
        ),
      );
    }

    void saveInlineCodeEdits() {
      final fileToSave = selectedFile;
      if (fileToSave == null) return;
      final savedResPath = fileToSave.resPath;
      final editedText = _codeFileEditorCtrl.text.replaceAll('\r\n', '\n');
      widget.workbench.upsertGodotVirtualFile(
        resPath: savedResPath,
        content: editedText,
        featureIds: [feat.id],
      );
      _rebuild(() {
        _editingCodeFileResPath = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved $savedResPath ✓'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    return Container(
      key: ValueKey('code_file_workspace_${node.id}'),
      margin: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF06090F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1F2B3E)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: const BoxDecoration(
              color: Color(0xFF0D1422),
              border: Border(bottom: BorderSide(color: Color(0xFF1F2B3E))),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final vf in displayedFiles)
                      InkWell(
                        key: ValueKey('code_mode_file_tab_${vf.resPath}'),
                        borderRadius: BorderRadius.circular(5),
                        onTap: () => _rebuild(() {
                          _isShowingStarterTscnInCodeMode = false;
                          _selectedCodeFileResPath = vf.resPath;
                          _editingCodeFileResPath = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (!showingTscn &&
                                    selectedFile.resPath == vf.resPath)
                                ? const Color(0xFF1B2740)
                                : const Color(0xFF090E18),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: (!showingTscn &&
                                      selectedFile.resPath == vf.resPath)
                                  ? const Color(0xFF38BDF8)
                                      .withValues(alpha: 0.6)
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          child: Text(
                            '📜 ${vf.resPath}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: (!showingTscn &&
                                      selectedFile.resPath == vf.resPath)
                                  ? const Color(0xFF7DD3FC)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ),
                    if (otherFiles.isNotEmpty && featureFiles.isNotEmpty)
                      InkWell(
                        key: ValueKey('code_mode_toggle_all_files_${node.id}'),
                        borderRadius: BorderRadius.circular(5),
                        onTap: () => _rebuild(() {
                          _showAllProjectFilesInCodeMode =
                              !_showAllProjectFilesInCodeMode;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF090E18),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: const Color(0xFF26334D)),
                          ),
                          child: Text(
                            _showAllProjectFilesInCodeMode
                                ? 'Feature Only'
                                : '+ ${otherFiles.length} Project Files',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ),
                    InkWell(
                      key: ValueKey('code_mode_starter_tscn_tab_${node.id}'),
                      borderRadius: BorderRadius.circular(5),
                      onTap: () => _rebuild(() {
                        _isShowingStarterTscnInCodeMode = true;
                        _editingCodeFileResPath = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: showingTscn
                              ? const Color(0xFF0A241C)
                              : const Color(0xFF090E18),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: showingTscn
                                ? const Color(0xFF34D399).withValues(alpha: 0.6)
                                : const Color(0xFF1E293B),
                          ),
                        ),
                        child: Text(
                          isUnsavedScaffoldFallback
                              ? '🌲 Starter .tscn (Unsaved)'
                              : '🌲 Starter .tscn',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: showingTscn
                                ? const Color(0xFF6EE7B7)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (isUnsavedScaffoldFallback) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1A0E),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'Unsaved Scaffold · No .gd saved yet',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: weightSemi,
                            color: const Color(0xFFFCD34D),
                          ),
                        ),
                      ),
                      toolbarBtn(
                        key: ValueKey(
                          'code_mode_create_starter_gd_btn_${node.id}',
                        ),
                        label: '+ Create Starter .gd',
                        fgColor: const Color(0xFF6EE7B7),
                        bgColor: const Color(0xFF0A241C),
                        borderColor:
                            const Color(0xFF34D399).withValues(alpha: 0.5),
                        bold: true,
                        onTap: () {
                          final snake = TaskHowToBlueprint
                              .deriveConcreteAssetName(feat.title)
                              .snakeName;
                          final targetPath = primaryScript ??
                              (defaultRes.endsWith('.gd')
                                  ? defaultRes
                                  : 'res://scripts/${snake.isNotEmpty ? snake : 'feature'}.gd');
                          final scaffold =
                              GodotVirtualFile.buildGdStarterScaffold(
                            baseClass: assetSpec.parentClassLabel,
                            scriptTitle: feat.title,
                            tuningParams: tuningItems,
                            stepTitles:
                                unifiedSteps.map((s) => s.shortTitle).toList(),
                          );
                          widget.workbench.upsertGodotVirtualFile(
                            resPath: targetPath,
                            content: scaffold,
                            featureIds: [feat.id],
                          );
                          _rebuild(() {
                            _isShowingStarterTscnInCodeMode = false;
                            _selectedCodeFileResPath = targetPath;
                            _editingCodeFileResPath = null;
                          });
                        },
                      ),
                    ],
                    if (isEditingActiveFile) ...[
                      toolbarBtn(
                        key: ValueKey('code_mode_save_btn_${node.id}'),
                        label: '✓ Save',
                        fgColor: const Color(0xFF6EE7B7),
                        bgColor: const Color(0xFF0A241C),
                        borderColor:
                            const Color(0xFF34D399).withValues(alpha: 0.55),
                        bold: true,
                        onTap: saveInlineCodeEdits,
                      ),
                      toolbarBtn(
                        key: ValueKey('code_mode_cancel_edit_btn_${node.id}'),
                        label: 'Cancel',
                        fgColor: const Color(0xFF94A3B8),
                        onTap: () => _rebuild(() {
                          _editingCodeFileResPath = null;
                        }),
                      ),
                    ] else ...[
                      if (!showingTscn)
                        toolbarBtn(
                          key: ValueKey('code_mode_edit_btn_${node.id}'),
                          label: '✎ Edit',
                          fgColor: const Color(0xFFFDE68A),
                          bgColor: const Color(0xFF1D160B),
                          borderColor:
                              const Color(0xFFF59E0B).withValues(alpha: 0.45),
                          bold: true,
                          onTap: () {
                            final fileToEdit = selectedFile;
                            if (fileToEdit == null) return;
                            _codeFileEditorCtrl.text = fileToEdit.content;
                            _rebuild(() {
                              _editingCodeFileResPath = fileToEdit.resPath;
                            });
                          },
                        ),
                      toolbarBtn(
                        key: ValueKey('code_mode_copy_btn_${node.id}'),
                        label: showingTscn ? '⧉ Copy .tscn' : '⧉ Copy Full .gd',
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: activeContent));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied $activePath to clipboard ✓'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                      toolbarBtn(
                        key: ValueKey('code_mode_download_btn_${node.id}'),
                        label: showingTscn ? '⬇ Download .tscn' : '⬇ Download .gd',
                        fgColor: const Color(0xFF7DD3FC),
                        bgColor: const Color(0xFF0E293D),
                        borderColor:
                            const Color(0xFF38BDF8).withValues(alpha: 0.45),
                        bold: true,
                        onTap: () {
                          final fileName = activePath.split('/').last;
                          final downloaded = triggerMarkdownFileDownload(
                            filename: fileName,
                            content: activeContent,
                          );
                          if (!downloaded) {
                            Clipboard.setData(ClipboardData(text: activeContent));
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  downloaded
                                      ? 'Downloaded $fileName ✓'
                                      : 'Copied $activePath to clipboard ✓',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isEditingActiveFile)
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                key: ValueKey('code_mode_editor_input_${node.id}'),
                controller: _codeFileEditorCtrl,
                autofocus: true,
                maxLines: null,
                minLines: 12,
                keyboardType: TextInputType.multiline,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: fontBody,
                  color: textPrimary,
                  height: 1.6,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF090E18),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: Color(0xFF283854)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < lines.length; i++)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            (i + 1).toString().padLeft(2, '0'),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: fontMicro,
                              color: const Color(0xFF475569),
                              height: 1.65,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text.rich(
                            _buildSemanticStepSpan(
                              text: lines[i],
                              baseStyle: GoogleFonts.jetBrainsMono(
                                fontSize: fontBody,
                                fontWeight: weightRegular,
                                color: textPrimary,
                                height: 1.65,
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
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveSynthesisPlaceholder({
    required TierDocument feat,
    required bool isHalfScreenOverlayMode,
    required bool isSynthesizingFeatureNow,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isHalfScreenOverlayMode)
          SizedBox(
            width: 268,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Container(
                key: ValueKey('feature_steps_in_progress_${feat.id}'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bgRecessed,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'BUILD QUEUE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: textMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isSynthesizingFeatureNow
                              ? const Color(0xFFFBBF24)
                              : textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isSynthesizingFeatureNow
                          ? 'In Progress'
                          : 'Waiting in Queue',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            decoration: BoxDecoration(
              color: bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderSubtle),
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
                      ? 'Generating Dock-ordered Build Queue steps…'
                      : 'Queued behind active build.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: textMuted,
                  ),
                ),
                if (!isSynthesizingFeatureNow) ...[
                  const SizedBox(height: 14),
                  OutlinedButton(
                    key: ValueKey('build_queued_feature_now_btn_${feat.id}'),
                    onPressed: () {
                      widget.workbench.synthesizeFeatureHowToStepsWithAi(
                        feat.id,
                      );
                    },
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
        ),
      ],
    );
  }

  List<String> _computeUpgradeDeltaChips(
    List<FeatureStateNode> states,
    int index,
    FeatureStateNode node,
  ) {
    final chips = <String>[];
    if (index <= 0 || index >= states.length) return chips;
    final prevState = states[index - 1];
    final prevMap = <String, String>{};
    for (final raw in prevState.tuningParams) {
      final p = raw.split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex);
      final k = p.first.trim();
      if (k.isNotEmpty) {
        prevMap[k.toLowerCase()] =
            p.length > 1 ? p.sublist(1).join(':').trim() : '';
      }
    }
    for (final raw in node.tuningParams) {
      final p = raw.split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex);
      final k = p.first.trim();
      if (k.isEmpty) continue;
      final curVal = p.length > 1 ? p.sublist(1).join(':').trim() : '';
      final prevVal = prevMap[k.toLowerCase()];
      if (prevVal == null) {
        chips.add('+$k: $curVal');
      } else if (prevVal != curVal) {
        chips.add('$k: $prevVal → $curVal');
      }
    }
    return chips;
  }

  Widget _buildInlinePlaytestBugDrawer({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int index,
    required FeatureStateNode node,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF191412),
        border: Border(bottom: BorderSide(color: Color(0x4DF59E0B))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Log Playtest Issue:',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFBBF24),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: ValueKey('feature_gate_bug_input_${node.id}'),
                  controller: _inlineBugInputCtrl,
                  style: GoogleFonts.inter(fontSize: 12.5, color: textPrimary),
                  decoration: InputDecoration(
                    hintText:
                        'Describe bug or paste Godot Debugger trace (res://...gd:42)...',
                    hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                    filled: true,
                    fillColor: bgRecessed,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderSubtle),
                    ),
                  ),
                  onSubmitted: (_) =>
                      _submitInlinePlaytestBug(feat, states, index, node),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: ValueKey('feature_gate_bug_submit_btn_${node.id}'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => _submitInlinePlaytestBug(feat, states, index, node),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    '+ Add [FIX] Step',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFBBF24),
                    ),
                  ),
                ),
              ),
            ],
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _inlineBugInputCtrl,
            builder: (ctx, val, _) {
              final parsed = GodotGdscriptGuard.parseDebuggerTrace(val.text);
              if (parsed == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  key: ValueKey('debugger_trace_chip_${node.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.38),
                    ),
                  ),
                  child: Text(
                    parsed.summaryChipLabel,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF7DD3FC),
                    ),
                  ),
                ),
              );
            },
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
    bool fillViewportHeight = false,
  }) {
    if (widget.workbench.focusMode && index != activeFocusIndex) {
      return const SizedBox.shrink();
    }

    final node = states[index];
    final featureGoalText = TaskHowToBlueprint.formatConciseFeatureGoal(
      SectionTextUtils.resolveGoal(feat.sections),
    );
    final tuningItems = node.tuningParams;
    final edgeItems = node.edgeCases;
    final currentPhase = widget.workbench.currentPhase;
    final unifiedSteps = TaskHowToBlueprint.resolveUnifiedSteps(
      checkpointNode: node,
      engineHint: _engineHint,
      phase: currentPhase,
    );
    final activeStepIdx = _resolveFlatStepIndex(node, unifiedSteps);
    final isPlaytestGate = _isPlaytestGateSelected(node, unifiedSteps);
    final activeSubStep = unifiedSteps.isNotEmpty
        ? unifiedSteps[activeStepIdx.clamp(0, unifiedSteps.length - 1)]
        : TaskHowToSubStep(
            subtask: Subtask(id: 'empty', text: feat.title),
            stepNumberLabel: '01',
            instruction: '',
            codeFormula: '',
          );

    final canGoPrev = index > 0 || isPlaytestGate || activeStepIdx > 0;
    final canGoNext = index + 1 < states.length ||
        (!isPlaytestGate && unifiedSteps.isNotEmpty);

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
    final featShortTitle = _formatOutlineFeatureDisplayTitle(
      feat.title,
      parentBeatTitle,
      beatIndex: parentBeatIdx,
    );

    final activeTargetComp = _resolveStepTargetComponent(
      activeSubStep,
      featTitle: feat.title,
    );
    final assetSpec = _resolveFeatureAssetSpec(
      feat: feat,
      checkpointIndex: index,
      activeStepIdx: activeStepIdx,
      activeSubStep: activeSubStep,
      activeTargetComp: activeTargetComp,
    );

    final isFeatureBeingBuiltInLiveMode =
        widget.workbench.isFeatureBeingBuiltInLiveMode(feat.id);
    final isSynthesizingFeatureNow =
        widget.workbench.isSynthesizingFeatureSteps(feat.id);

    final Widget doneBtn = _buildUnifiedDoneButton(
      feat: feat,
      states: states,
      node: node,
      unifiedSteps: unifiedSteps,
      activeStepIdx: activeStepIdx,
      isPlaytestGate: isPlaytestGate,
      isHalfScreenOverlayMode: isHalfScreenOverlayMode,
    );
    final Widget featureActionsMenu = _buildFeatureActionsMenu(
      feat: feat,
      states: states,
      checkpointIndex: index,
      node: node,
      activeStepIdx: activeStepIdx,
      isHalfScreen: isHalfScreenOverlayMode,
    );

    final upgradeDeltaChips = _computeUpgradeDeltaChips(states, index, node);
    final isDrawerOpen = _inlineBugDrawerNodeId == node.id;

    return Container(
      key: ValueKey('checkpoint_single_col_$index'),
      margin: const EdgeInsets.only(bottom: 6),
      child: Container(
        key: ValueKey('checkpoint_spec_pane_$index'),
        child: Container(
          key: ValueKey('pinned_active_step_window_${node.id}'),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0D14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF1F2B3E),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isHalfScreenOverlayMode)
                _buildSplitScreenFloatingHeader(
                  feat: feat,
                  states: states,
                  index: index,
                  node: node,
                  unifiedSteps: unifiedSteps,
                  activeStepIdx: activeStepIdx,
                  isPlaytestGate: isPlaytestGate,
                  canGoPrev: canGoPrev,
                  canGoNext: canGoNext,
                  isFeatureBeingBuiltInLiveMode: isFeatureBeingBuiltInLiveMode,
                  isSynthesizingFeatureNow: isSynthesizingFeatureNow,
                  epicShortCode: epicShortCode,
                  featShortTitle: featShortTitle,
                  featureGoalText: featureGoalText,
                  doneBtn: doneBtn,
                  featureActionsMenu: featureActionsMenu,
                )
              else
                _buildDesktopSlimFeatureHeader(
                  feat: feat,
                  states: states,
                  index: index,
                  node: node,
                  unifiedSteps: unifiedSteps,
                  activeStepIdx: activeStepIdx,
                  isPlaytestGate: isPlaytestGate,
                  canGoPrev: canGoPrev,
                  canGoNext: canGoNext,
                  isSynthesizingFeatureNow: isSynthesizingFeatureNow,
                  epicShortCode: epicShortCode,
                  featShortTitle: featShortTitle,
                  featureGoalText: featureGoalText,
                  assetSpec: assetSpec,
                  doneBtn: doneBtn,
                  featureActionsMenu: featureActionsMenu,
                ),

              if (upgradeDeltaChips.isNotEmpty)
                Container(
                  key: ValueKey('desktop_upgrade_delta_strip_${node.id}'),
                  padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0F18),
                    border: Border(
                      bottom: BorderSide(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Δ FROM ${states[index - 1].releaseVersion}:',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF38BDF8),
                        ),
                      ),
                      Text(
                        upgradeDeltaChips.join(' · '),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFFCBD5E1),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_activeStage2InlineEditKey == 'workspace_add_task_${node.id}')
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0E131D),
                    border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'STAGE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            for (final stage in const [
                              GodotDockStage.scene,
                              GodotDockStage.inspector,
                              GodotDockStage.code,
                              GodotDockStage.wire,
                            ])
                              InkWell(
                                key: ValueKey('add_step_stage_${stage.name}'),
                                borderRadius: BorderRadius.circular(5),
                                onTap: () => _rebuild(
                                  () => _inlineAddStepStage = stage,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _inlineAddStepStage == stage
                                        ? const Color(0xFF172554)
                                        : const Color(0xFF161E2E),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: _inlineAddStepStage == stage
                                          ? const Color(0xFF38BDF8)
                                          : const Color(0xFF283548),
                                    ),
                                  ),
                                  child: Text(
                                    stage.badge,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                      color: _inlineAddStepStage == stage
                                          ? const Color(0xFF7DD3FC)
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      _buildStage2InlineEditor(
                        editKey: 'workspace_add_task_${node.id}',
                        inputKey: const ValueKey('add_stage3_task_title_input'),
                        saveBtnKey: const ValueKey(
                          'confirm_add_stage3_task_btn',
                        ),
                        hintText: 'Add unified step (e.g. Add coyote timer)…',
                        onSave: (val) => _commitInlineAddBuildTask(
                          feat,
                          states,
                          index,
                          val,
                          dockStage: _inlineAddStepStage,
                        ),
                      ),
                    ],
                  ),
                ),

              if (isDrawerOpen)
                _buildInlinePlaytestBugDrawer(
                  feat: feat,
                  states: states,
                  index: index,
                  node: node,
                ),

              if (widget.workbench.hasFailedStepSynthesis(feat.id) &&
                  !isSynthesizingFeatureNow)
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF1E293B)),
                    ),
                  ),
                  child: InkWell(
                    key: ValueKey('retry_ai_steps_banner_${feat.id}'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => widget.workbench
                        .synthesizeFeatureHowToStepsWithAi(
                      feat.id,
                      forceRefresh: true,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              '✦ Engine Steps Timed Out — Showing preview steps',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: fontMicro,
                                fontWeight: weightSemi,
                                color: const Color(0xFFFCD34D),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Retry ↻',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: fontMicro,
                              fontWeight: weightBold,
                              color: const Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (isFeatureBeingBuiltInLiveMode)
                fillViewportHeight
                    ? Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(
                            isHalfScreenOverlayMode ? 12 : 16,
                          ),
                          child: _buildLiveSynthesisPlaceholder(
                            feat: feat,
                            isHalfScreenOverlayMode: isHalfScreenOverlayMode,
                            isSynthesizingFeatureNow: isSynthesizingFeatureNow,
                          ),
                        ),
                      )
                    : Padding(
                        padding: EdgeInsets.all(
                          isHalfScreenOverlayMode ? 12 : 16,
                        ),
                        child: _buildLiveSynthesisPlaceholder(
                          feat: feat,
                          isHalfScreenOverlayMode: isHalfScreenOverlayMode,
                          isSynthesizingFeatureNow: isSynthesizingFeatureNow,
                        ),
                      )
              else if (_isCodeFileWorkspaceMode)
                fillViewportHeight
                    ? Expanded(
                        child: SingleChildScrollView(
                          child: _buildCodeFileWorkspaceView(
                            feat: feat,
                            node: node,
                            unifiedSteps: unifiedSteps,
                            activeTargetComp: activeTargetComp,
                            assetSpec: assetSpec,
                            tuningItems: tuningItems,
                            edgeItems: edgeItems,
                          ),
                        ),
                      )
                    : _buildCodeFileWorkspaceView(
                        feat: feat,
                        node: node,
                        unifiedSteps: unifiedSteps,
                        activeTargetComp: activeTargetComp,
                        assetSpec: assetSpec,
                        tuningItems: tuningItems,
                        edgeItems: edgeItems,
                      )
              else if (isHalfScreenOverlayMode)
                fillViewportHeight
                    ? Expanded(
                        child: SingleChildScrollView(
                          child: _buildCheckpointDetailPane(
                            feat: feat,
                            states: states,
                            checkpointIndex: index,
                            node: node,
                            unifiedSteps: unifiedSteps,
                            activeStepIdx: activeStepIdx,
                            isPlaytestGate: isPlaytestGate,
                            tuningItems: tuningItems,
                            edgeItems: edgeItems,
                          ),
                        ),
                      )
                    : _buildCheckpointDetailPane(
                        feat: feat,
                        states: states,
                        checkpointIndex: index,
                        node: node,
                        unifiedSteps: unifiedSteps,
                        activeStepIdx: activeStepIdx,
                        isPlaytestGate: isPlaytestGate,
                        tuningItems: tuningItems,
                        edgeItems: edgeItems,
                      )
              else if (fillViewportHeight)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBuildQueueRail(
                        feat: feat,
                        states: states,
                        index: index,
                        node: node,
                        unifiedSteps: unifiedSteps,
                        activeStepIdx: activeStepIdx,
                        isPlaytestGate: isPlaytestGate,
                        edgeItems: edgeItems,
                        fillHeight: true,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _buildCheckpointDetailPane(
                            feat: feat,
                            states: states,
                            checkpointIndex: index,
                            node: node,
                            unifiedSteps: unifiedSteps,
                            activeStepIdx: activeStepIdx,
                            isPlaytestGate: isPlaytestGate,
                            tuningItems: tuningItems,
                            edgeItems: edgeItems,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBuildQueueRail(
                      feat: feat,
                      states: states,
                      index: index,
                      node: node,
                      unifiedSteps: unifiedSteps,
                      activeStepIdx: activeStepIdx,
                      isPlaytestGate: isPlaytestGate,
                      edgeItems: edgeItems,
                    ),
                    Expanded(
                      child: _buildCheckpointDetailPane(
                        feat: feat,
                        states: states,
                        checkpointIndex: index,
                        node: node,
                        unifiedSteps: unifiedSteps,
                        activeStepIdx: activeStepIdx,
                        isPlaytestGate: isPlaytestGate,
                        tuningItems: tuningItems,
                        edgeItems: edgeItems,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckpointDetailPane({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required FeatureStateNode node,
    required List<TaskHowToSubStep> unifiedSteps,
    required int activeStepIdx,
    required bool isPlaytestGate,
    required List<String> tuningItems,
    required List<String> edgeItems,
  }) {
    return isPlaytestGate
        ? _buildPlaytestGateWorkspacePane(
            feat: feat,
            states: states,
            node: node,
            unifiedSteps: unifiedSteps,
            edgeItems: edgeItems,
            tuningItems: tuningItems,
          )
        : _buildEngineStepAreasBox(
            feat: feat,
            states: states,
            checkpointIndex: checkpointIndex,
            node: node,
            unifiedSteps: unifiedSteps,
            activeStepIdx: activeStepIdx,
            tuningItems: tuningItems,
            edgeItems: edgeItems,
          );
  }
}
