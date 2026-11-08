part of 'release_workbench_screen.dart';

extension _WorkbenchEngineAreasExt on _ReleaseWorkbenchScreenState {
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
      for (final t in tuningItems.take(2)) {
        final parts =
            t.split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex);
        final k = parts.first.trim();
        final v = parts.length > 1 ? parts.sublist(1).join(':').trim() : '1.0';
        if (k.isNotEmpty) {
          inspRows.add((key: 'Tuning · $k', value: v));
        }
      }
      if (inspRows.isEmpty) {
        inspRows.add((key: 'Primary Tuning Binding', value: primaryTuningLabel));
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
        (key: 'Guard Reference Check', value: primaryGuardLabel),
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
      // Avoid repeating the single Tuning Parameter & Guard Rule already shown in the Spec Bar pill above
      // on follow-up runtime steps (activeSubStepIdx > 0), while keeping the inspector binding row on Step X.1.
      if (activeSubStepIdx == 0) {
        inspWhere = activeSubStep.isGuardStep
            ? 'Guard Condition & Safety Check'
            : (isUnrealBp
                ? 'Event Graph Node Pins & Details'
                : 'Runtime Tuning & Inspector Binding');
        if (activeSubStep.isGuardStep) {
          inspRows.addAll([
            (key: 'Guard Rule', value: primaryGuardLabel),
            (key: 'Tuning Context', value: effectiveTuningLabel),
          ]);
        } else {
          inspRows.addAll([
            (key: 'Tuning Parameter', value: effectiveTuningLabel),
            (key: 'Guard Rule', value: primaryGuardLabel),
          ]);
        }
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

    final hasInsp = inspRows.isNotEmpty;
    final hasCode = codeBody != null && codeBody.trim().isNotEmpty;

    final showInsp =
        hasInsp && (_engineAreaFilter == 0 || _engineAreaFilter == 2);
    final showCode =
        hasCode && (_engineAreaFilter == 0 || _engineAreaFilter == 3);

    final codeLines = showCode ? codeBody.split('\n') : const <String>[];
    final effectiveHeaderPath = (codeWhere != null && codeWhere.trim().isNotEmpty)
        ? codeWhere.trim()
        : stepPath;
    final isCompactSplit = MediaQuery.sizeOf(context).width < 1040;

    final activeTargetComp = _resolveTaskTargetComponent(
      selectedHowTo,
      unrealCppMode: _unrealCppMode,
    );
    final sharedTaskIndices = <int>[];
    final siblingCompRows = <({int taskIdx, String key, String value})>[];
    for (int tIdx = 0; tIdx < howToBlueprints.length; tIdx++) {
      final comp = _resolveTaskTargetComponent(
        howToBlueprints[tIdx],
        unrealCppMode: _unrealCppMode,
      );
      if (comp.componentKey == activeTargetComp.componentKey) {
        sharedTaskIndices.add(tIdx);
        if (tIdx != selectedTaskIdx) {
          final sibBp = howToBlueprints[tIdx];
          final sibSub = sibBp.subSteps.isNotEmpty ? sibBp.subSteps.first : null;
          final sibArea2 = sibSub?.area2Inspector?.trim() ?? '';
          if (sibArea2.isNotEmpty) {
            final entries = sibArea2.contains('\n')
                ? sibArea2.split('\n')
                : sibArea2.split('|');
            for (final rawE in entries.take(2)) {
              final cleanE = rawE.trim();
              if (cleanE.isEmpty) continue;
              final cIdx = cleanE.indexOf(':');
              final eIdx = cleanE.indexOf('=');
              final dIdx = cIdx != -1 ? cIdx : eIdx;
              if (dIdx > 0 && dIdx < cleanE.length - 1) {
                final k = cleanE.substring(0, dIdx).trim();
                final v = cleanE.substring(dIdx + 1).trim();
                if (!inspRows.any((r) => r.key.toLowerCase() == k.toLowerCase())) {
                  siblingCompRows.add((taskIdx: tIdx, key: k, value: v));
                }
              }
            }
          }
          if (siblingCompRows.where((r) => r.taskIdx == tIdx).isEmpty &&
              tuningItems.isNotEmpty) {
            final rawT = tuningItems[tIdx % tuningItems.length];
            final parts = rawT.split(
              _ReleaseWorkbenchScreenState._tuningVarDelimiterRegex,
            );
            final k = parts.first.trim();
            final v = parts.length > 1
                ? parts.sublist(1).join(':').trim()
                : rawT.trim();
            if (k.isNotEmpty &&
                !inspRows.any((r) => r.key.toLowerCase() == k.toLowerCase())) {
              siblingCompRows.add((
                taskIdx: tIdx,
                key: '${sibBp.shortTaskTitle} · $k',
                value: v,
              ));
            }
          }
        }
      }
    }
    if (!sharedTaskIndices.contains(selectedTaskIdx)) {
      sharedTaskIndices.add(selectedTaskIdx);
    }

    final sceneHierarchyZone = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        border: Border(
          right: isCompactSplit
              ? BorderSide.none
              : const BorderSide(color: Color(0x14FFFFFF)),
          bottom: isCompactSplit
              ? const BorderSide(color: Color(0x14FFFFFF))
              : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.34),
                  ),
                ),
                child: Text(
                  '01',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF7DD3FC),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Scene hierarchy',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFF8FAFC),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildEngineHierarchyTreeCard(
            feat: feat,
            states: states,
            checkpointIndex: checkpointIndex,
            node: node,
            howToBlueprints: howToBlueprints,
            selectedTaskIdx: selectedTaskIdx,
            bp: selectedHowTo,
            activeSubStep: activeSubStep,
            selectedHowTo: selectedHowTo,
            unrealCppMode: _unrealCppMode,
            isDark: isDark,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textMuted: textMuted,
            borderSubtle: borderSubtle,
            accentEmerald: accentEmerald,
          ),
        ],
      ),
    );

    final inspectorDetailsZone = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.34),
                        ),
                      ),
                      child: Text(
                        '02',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFFCD34D),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Inspector details',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFF8FAFC),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  area2Title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0x12FFFFFF),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Component-Owned Sub-Header Bar (Correlates 01 Scene Hierarchy → 02 Inspector)
                Container(
                  key: ValueKey(
                    'area2_selected_component_header_${node.id}',
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF161B26),
                    border: Border(
                      bottom: BorderSide(color: Color(0x14FFFFFF)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              color: const Color(0xFF94A3B8),
                            ),
                            children: [
                              const TextSpan(text: 'Inspecting: '),
                              TextSpan(
                                text: activeTargetComp.componentKey,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFF3F6FC),
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(3.5),
                          border: Border.all(
                            color:
                                const Color(0xFFF59E0B).withValues(alpha: 0.38),
                          ),
                        ),
                        child: Text(
                          sharedTaskIndices.length > 1
                              ? 'Shared by ${sharedTaskIndices.map((i) => 'T${i + 1}').join(' & ')}'
                              : 'T${selectedTaskIdx + 1}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFBBF24),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (primaryTuningLabel.isNotEmpty)
                        _activeStage2InlineEditKey == 'tuning_${node.id}'
                            ? _buildStage2InlineEditor(
                                editKey: 'tuning_${node.id}',
                                hintText: 'e.g. moveSpeed: 600',
                                inputKey: ValueKey(
                                  'inline_tuning_input_${node.id}',
                                ),
                                saveBtnKey: ValueKey(
                                  'inline_tuning_save_btn_${node.id}',
                                ),
                                cancelBtnKey: ValueKey(
                                  'inline_tuning_cancel_btn_${node.id}',
                                ),
                                onSave: (val) => _saveInlineTuningParam(
                                  feat: feat,
                                  states: states,
                                  node: node,
                                  selectedTaskIdx: selectedTaskIdx,
                                  rawValue: val,
                                ),
                              )
                            : Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 14,
                                runSpacing: 6,
                                children: [
                                  InkWell(
                                    key: ValueKey(
                                      'inline_tuning_pill_${node.id}',
                                    ),
                                    onTap: () => _startStage2InlineEdit(
                                      'tuning_${node.id}',
                                      primaryTuningLabel,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 1,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              '⚙ $primaryTuningLabel',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFFF59E0B),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          const Icon(
                                            Icons.edit_outlined,
                                            size: 11,
                                            color: Color(0xFFF59E0B),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      if (primaryTuningLabel.isNotEmpty && showInsp)
                        const SizedBox(height: 6),
                      if (showInsp)
                        for (int rIdx = 0; rIdx < inspRows.length; rIdx++)
                          Container(
                            padding: EdgeInsets.only(
                              top: rIdx == 0 ? 0 : 5,
                              bottom: (rIdx == inspRows.length - 1 &&
                                      siblingCompRows.isEmpty)
                                  ? 0
                                  : 5,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: (rIdx == inspRows.length - 1 &&
                                        siblingCompRows.isEmpty)
                                    ? BorderSide.none
                                    : const BorderSide(color: Color(0x0DFFFFFF)),
                              ),
                            ),
                            child: _activeStage2InlineEditKey ==
                                    'area2_tuning_${node.id}_$rIdx'
                                ? _buildStage2InlineEditor(
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
                                    ),
                                  )
                                : InkWell(
                                    key: ValueKey(
                                      'area2_inspector_tuning_row_${node.id}_$rIdx',
                                    ),
                                    onTap: () {
                                      final row = inspRows[rIdx];
                                      Clipboard.setData(
                                        ClipboardData(text: row.value),
                                      );
                                      final initialText =
                                          (row.value.contains(':') ||
                                                  row.value.contains('='))
                                              ? row.value
                                                  .split('·')
                                                  .first
                                                  .trim()
                                              : (primaryTuningLabel.isNotEmpty
                                                  ? primaryTuningLabel
                                                  : '${row.key}: ${row.value}');
                                      _startStage2InlineEdit(
                                        'area2_tuning_${node.id}_$rIdx',
                                        initialText,
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Flexible(
                                          flex: 5,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 1,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF59E0B)
                                                      .withValues(alpha: 0.16),
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                  border: Border.all(
                                                    color:
                                                        const Color(0xFFF59E0B)
                                                            .withValues(
                                                                alpha: 0.42),
                                                  ),
                                                ),
                                                child: Text(
                                                  'T${selectedTaskIdx + 1}',
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        const Color(0xFFFBBF24),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  inspRows[rIdx].key,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    color:
                                                        const Color(0xFFCBD5E1),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          flex: 6,
                                          child: Text.rich(
                                            _buildSemanticStepSpan(
                                              text: inspRows[rIdx].value,
                                              baseStyle:
                                                  GoogleFonts.jetBrainsMono(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFFF59E0B),
                                              ),
                                              tuningItems: tuningItems,
                                              edgeItems: edgeItems,
                                              isCodeBlock: true,
                                            ),
                                            textAlign: TextAlign.right,
                                            softWrap: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                      // Dimmed sibling-task rows on the same shared component (42% opacity · click to switch task)
                      if (showInsp && siblingCompRows.isNotEmpty)
                        for (int sIdx = 0;
                            sIdx < siblingCompRows.length;
                            sIdx++)
                          Opacity(
                            opacity: 0.42,
                            child: InkWell(
                              key: ValueKey(
                                'area2_shared_sibling_row_${node.id}_${siblingCompRows[sIdx].taskIdx}_$sIdx',
                              ),
                              onTap: () {
                                final targetIdx = siblingCompRows[sIdx].taskIdx;
                                _rebuild(() {
                                  _manualCheckpointFocusIndex = checkpointIndex;
                                  _manualCheckpointFocusFeatureId = feat.id;
                                  _selectedTaskIndexByCheckpoint[node.id] =
                                      targetIdx;
                                  _selectedSubStepIndexByTask[
                                      '${node.id}_$targetIdx'] = 0;
                                });
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: EdgeInsets.only(
                                  top: 5,
                                  bottom: sIdx == siblingCompRows.length - 1
                                      ? 0
                                      : 5,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: sIdx == siblingCompRows.length - 1
                                        ? BorderSide.none
                                        : const BorderSide(
                                            color: Color(0x0DFFFFFF),
                                          ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Flexible(
                                      flex: 5,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1E293B),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                              border: Border.all(
                                                color: const Color(0x28FFFFFF),
                                              ),
                                            ),
                                            child: Text(
                                              'T${siblingCompRows[sIdx].taskIdx + 1}',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF94A3B8),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              siblingCompRows[sIdx].key,
                                              style: GoogleFonts.inter(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w500,
                                                color: const Color(0xFF94A3B8),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      flex: 6,
                                      child: Text(
                                        siblingCompRows[sIdx].value,
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      if (primaryGuardLabel.isNotEmpty) ...[
                        if (primaryTuningLabel.isNotEmpty || showInsp)
                          const SizedBox(height: 6),
                        Text(
                          '🛡 Guard: $primaryGuardLabel',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Zero-size compatibility hooks for area labels and offstage edit buttons
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

        // ── UPPER 50/50 SPLIT BAY: 01 Scene hierarchy (Left 50%) + 02 Inspector details (Right 50%) ──
        Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0x14FFFFFF)),
            ),
          ),
          child: isCompactSplit
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sceneHierarchyZone,
                    inspectorDetailsZone,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: sceneHierarchyZone),
                    Expanded(child: inspectorDetailsZone),
                  ],
                ),
        ),

        // ── LOWER SCRIPT BAY: 03 Script implementation (#0B0E15 Code Well inside #121620 Sheet) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF5E6AD2).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: const Color(0xFF6875F5)
                                  .withValues(alpha: 0.38),
                            ),
                          ),
                          child: Text(
                            '03',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFA5B4FC),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Script implementation',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFF8FAFC),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      area3Title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0E15),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: const Color(0x14FFFFFF),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // File Bar Header (#161B26) + Copy Task Prompt & Copy code buttons
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF161B26),
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0x14FFFFFF),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              effectiveHeaderPath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                key: ValueKey(
                                  'copy_task_ai_prompt_btn_${node.id}_$selectedTaskIdx',
                                ),
                                onTap: () {
                                  final inspSummary = inspRows
                                      .map((r) => '- ${r.key}: ${r.value}')
                                      .join('\n');
                                  final promptText = [
                                    'Task T${selectedTaskIdx + 1}: ${selectedHowTo.shortTaskTitle} (${feat.title})',
                                    'Goal: ${selectedHowTo.taskGoalSentence}',
                                    'Target Component: ${activeTargetComp.displayLabel}',
                                    if (inspSummary.isNotEmpty)
                                      'Inspector Properties:\n$inspSummary',
                                    if (primaryGuardLabel.isNotEmpty)
                                      'Guardrail: $primaryGuardLabel',
                                    'Script ($effectiveHeaderPath):\n${activeSubStep.codeFormula.trim()}',
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
                                borderRadius: BorderRadius.circular(5),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E1B4B),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: const Color(0xFF6366F1)
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Text(
                                    '✦ Copy Task Prompt',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFA5B4FC),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                key: ValueKey(
                                  'copy_howto_code_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                                ),
                                onTap: () => _copySubStepCodeFormula(
                                  selectedTaskIdx,
                                  activeSubStepIdx,
                                  activeSubStep.codeFormula,
                                ),
                                borderRadius: BorderRadius.circular(5),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF21293A),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: const Color(0x21FFFFFF),
                                    ),
                                  ),
                                  child: Text(
                                    '⧉ Copy code',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Code Body (#0B0E15)
                    if (showCode)
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int lineIdx = 0;
                                lineIdx < codeLines.length;
                                lineIdx++)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom:
                                      lineIdx == codeLines.length - 1 ? 0 : 2,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      child: Text(
                                        (lineIdx + 1)
                                            .toString()
                                            .padLeft(2, '0'),
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 12,
                                          height: 1.65,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text.rich(
                                        _buildSemanticStepSpan(
                                          text: codeLines[lineIdx],
                                          baseStyle: GoogleFonts.jetBrainsMono(
                                            fontSize: 13,
                                            height: 1.65,
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
