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
    final primaryVarName = primaryTuningLabel.split(':').first.trim();

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
    final isTreeHierarchyStep = rawCode.contains('└─') ||
        rawCode.contains('├─') ||
        lowerPath.contains('scene dock') ||
        lowerPath.contains('hierarchy') ||
        lowerPath.contains('add child node') ||
        lowerPath.contains('create empty') ||
        lowerPath.contains('components panel');
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
      final key = t.split(':').first.trim().toLowerCase();
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
        final parts = t.split(':');
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
        if (colonIdx > 0 && colonIdx < cleanEntry.length - 1) {
          parsedAiRows.add((
            key: cleanEntry.substring(0, colonIdx).trim(),
            value: cleanEntry.substring(colonIdx + 1).trim(),
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

    final hasComp = compBody != null && compBody.trim().isNotEmpty;
    final hasInsp = inspRows.isNotEmpty;
    final hasCode = codeBody != null && codeBody.trim().isNotEmpty;

    Widget buildAreaPill({
      required String label,
      required bool active,
      required Color activeColor,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.12)
              : bgSurface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active
                ? activeColor.withValues(alpha: 0.42)
                : borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? activeColor
                    : textMuted.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: active ? activeColor : textMuted,
              ),
            ),
          ],
        ),
      );
    }

    Widget buildSectionHeader({
      required String title,
      required String whereBadge,
      required Color accentColor,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.015),
          border: Border(
            bottom: BorderSide(
              color: borderSubtle.withValues(alpha: 0.7),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderSubtle),
                ),
                child: Text(
                  whereBadge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bgBase,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Bar: 3 Engine-Specific Area Status Pills + 1-Click Copy / Edit
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: bgSurfaceHover,
              border: Border(
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      buildAreaPill(
                        label: '1. $area1Title',
                        active: hasComp,
                        activeColor: accentCyan,
                      ),
                      buildAreaPill(
                        label: '2. $area2Title',
                        active: hasInsp,
                        activeColor: accentViolet,
                      ),
                      buildAreaPill(
                        label: '3. $area3Title',
                        active: hasCode,
                        activeColor: accentEmerald,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message:
                          'On-demand gemini-flash-latest pass: adapt 3-Area Hierarchy, Inspector & Code to exact project variables and prior checkpoints',
                      child: InkWell(
                        key: const ValueKey('ai_adapt_three_area_btn'),
                        onTap: widget.workbench.isSynthesizingFeatureSteps(feat.id)
                            ? null
                            : () {
                                widget.workbench.synthesizeFeatureHowToStepsWithAi(
                                  feat.id,
                                  forceRefresh: true,
                                  unrealCppMode: _unrealCppMode,
                                );
                              },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          child: Text(
                            widget.workbench.isSynthesizingFeatureSteps(feat.id)
                                ? '✦ Adapting...'
                                : '✦ AI Adapt',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: accentAmber,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '·',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        color: textMuted,
                      ),
                    ),
                    InkWell(
                      key: ValueKey(
                        'copy_howto_code_${node.id}_${selectedTaskIdx}_$activeSubStepIdx',
                      ),
                      onTap: () => _copySubStepCodeFormula(
                        selectedTaskIdx,
                        activeSubStepIdx,
                        activeSubStep.codeFormula,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          '⧉ Copy',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: accentCyan,
                          ),
                        ),
                      ),
                    ),
                    if (activeSubStepIdx != 1)
                      Offstage(
                        offstage: true,
                        child: InkWell(
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
                      ),
                    Text(
                      '·',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        color: textMuted,
                      ),
                    ),
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
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          'Edit',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Section 1: Components & Outliner / Hierarchy / Scene Tree Dock (only when active in this step)
          if (hasComp)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: (hasInsp || hasCode)
                      ? BorderSide(color: borderSubtle)
                      : BorderSide.none,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildSectionHeader(
                    title: area1Title,
                    whereBadge: compWhere ?? stepPath,
                    accentColor: accentCyan,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text.rich(
                      _buildSemanticStepSpan(
                        text: compBody,
                        baseStyle: GoogleFonts.jetBrainsMono(
                          fontSize: 11.5,
                          height: 1.55,
                          color: isDark
                              ? const Color(0xFFE5E7EB)
                              : textPrimary,
                        ),
                        tuningItems: tuningItems,
                        edgeItems: edgeItems,
                        isCodeBlock: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Section 2: Details Panel / Inspector Window / Inspector Dock (only when active in this step)
          if (hasInsp)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: hasCode
                      ? BorderSide(color: borderSubtle)
                      : BorderSide.none,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildSectionHeader(
                    title: area2Title,
                    whereBadge: inspWhere,
                    accentColor: accentViolet,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int rIdx = 0; rIdx < inspRows.length; rIdx++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: rIdx == inspRows.length - 1 ? 0 : 6,
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
                                      final initialText = (row.value
                                                  .contains(':') ||
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
                                        horizontal: 2,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 196,
                                            child: Text(
                                              inspRows[rIdx].key,
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: textSecondary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text.rich(
                                              _buildSemanticStepSpan(
                                                text: inspRows[rIdx].value,
                                                baseStyle:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: textPrimary,
                                                ),
                                                tuningItems: tuningItems,
                                                edgeItems: edgeItems,
                                                isCodeBlock: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '✎',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 10,
                                              color: accentViolet.withValues(
                                                alpha: 0.75,
                                              ),
                                            ),
                                          ),
                                        ],
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

          // Section 3: Event Graph / C++ Source / C# MonoBehaviour / GDScript (only when active in this step)
          if (hasCode)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildSectionHeader(
                  title: area3Title,
                  whereBadge: codeWhere ?? stepPath,
                  accentColor: accentEmerald,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: Text.rich(
                    _buildSemanticStepSpan(
                      text: codeBody,
                      baseStyle: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        height: 1.58,
                        color: isDark
                            ? const Color(0xFFE5E7EB)
                            : textPrimary,
                      ),
                      tuningItems: tuningItems,
                      edgeItems: edgeItems,
                      isCodeBlock: true,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
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

    final specKey = '${tuningItems.join('\u0001')}\u0002${edgeItems.join('\u0001')}';
    if (specKey != _ReleaseWorkbenchScreenState._cachedSpecTokenKey) {
      final baseMap = <String, String>{};
      // 1. Tuning variable identifiers & full tuning specs -> 'tune' (Violet)
      for (final rawTune in tuningItems) {
        final trimmed = rawTune.trim();
        if (trimmed.isNotEmpty) {
          baseMap[trimmed] = 'tune';
          final varName = trimmed.split(':').first.trim();
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
      final kind = tokenKindByLiteral[matchedText] ?? 'asset';
      final Color tokenColor = kind == 'tune'
          ? accentViolet
          : (kind == 'guard' ? accentAmber : accentCyan);
      spans.add(
        TextSpan(
          text: matchedText,
          style: GoogleFonts.jetBrainsMono(
            fontSize: monoSize,
            fontWeight: FontWeight.w700,
            color: tokenColor,
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
