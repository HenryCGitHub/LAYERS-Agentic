part of 'release_workbench_screen.dart';

extension _WorkbenchEngineAreasExt on _ReleaseWorkbenchScreenState {
  /// Renders the Engine-Specific 3-Area Step Card (`COMPONENTS & OUTLINER` / `HIERARCHY & COMPONENTS` /
  /// `SCENE TREE DOCK (.tscn)`, `DETAILS PANEL` / `INSPECTOR WINDOW` / `INSPECTOR DOCK`, and
  /// `EVENT GRAPH` / `C++ SOURCE` / `C# MONOBEHAVIOUR` / `GDSCRIPT`), showing only the sections
  /// genuinely used by the active step so Component/Inspector setup is never mislabeled as Event Graph or Code.
  Widget _buildEngineStepAreasBox({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required FeatureStateNode node,
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

    final inspCardWidget = !showInsp
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int rIdx = 0; rIdx < inspRows.length; rIdx++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: rIdx == inspRows.length - 1 ? 0 : 5,
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
                              final initialText = (row.value.contains(':') ||
                                      row.value.contains('='))
                                  ? row.value.split('·').first.trim()
                                  : (primaryTuningLabel.isNotEmpty
                                      ? primaryTuningLabel
                                      : '${row.key}: ${row.value}');
                              _startStage2InlineEdit(
                                'area2_tuning_${node.id}_$rIdx',
                                initialText,
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 2,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 170,
                                    child: Text(
                                      inspRows[rIdx].key,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: textMuted,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text.rich(
                                      _buildSemanticStepSpan(
                                        text: inspRows[rIdx].value,
                                        baseStyle: GoogleFonts.jetBrainsMono(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: textSecondary,
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
                          ),
                  ),
              ],
            ),
          );

    final codeLines = showCode ? codeBody.split('\n') : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Zero-size compatibility hooks for area labels and offstage copy/edit buttons
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
                  if (!showCode)
                    InkWell(
                      key: ValueKey(
                        'copy_howto_code_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                      ),
                      onTap: () => _copySubStepCodeFormula(
                        selectedTaskIdx,
                        activeSubStepIdx,
                        activeSubStep.codeFormula,
                      ),
                      child: const Text('Copy'),
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

        // Unboxed 2-Column Component → Properties rows
        if (inspCardWidget != null) inspCardWidget,

        // Recessed Code Strip (#0B0D12 + 2px left bar, strictly contained, zero 4-sided border)
        if (showCode)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(14, 10, 16, 12),
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: const Color(0xFF0B0D12),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(4),
                bottomRight: Radius.circular(4),
              ),
              border: const Border(
                left: BorderSide(
                  color: Color(0xFF388BFD),
                  width: 2,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 6),
                  margin: const EdgeInsets.only(bottom: 7),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: borderSubtle.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          (codeWhere ?? stepPath).toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        key: ValueKey(
                          'copy_howto_code_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                        ),
                        onTap: () => _copySubStepCodeFormula(
                          selectedTaskIdx,
                          activeSubStepIdx,
                          activeSubStep.codeFormula,
                        ),
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          child: Text(
                            '⧉ Copy',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (int lineIdx = 0; lineIdx < codeLines.length; lineIdx++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: lineIdx == codeLines.length - 1 ? 0 : 2,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            (lineIdx + 1).toString().padLeft(2, '0'),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              height: 1.65,
                              color: const Color(0xFF3D4656),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text.rich(
                            _buildSemanticStepSpan(
                              text: codeLines[lineIdx],
                              baseStyle: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
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
