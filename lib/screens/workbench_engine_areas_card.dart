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
    String? inspWhere;
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
      final hasCameraSetup = rawCode.contains('CameraBoom') ||
          rawCode.contains('FollowCamera') ||
          rawCode.contains('CameraArm');
      final hasWeaponSetup =
          rawCode.contains('WeaponMesh') || rawCode.contains('MuzzlePoint');
      if (hasCameraSetup) {
        if (isUnreal) {
          inspRows.addAll([
            (
              key: 'CameraBoom → Target Arm Length',
              value: '400.0  ·  Do Collision Test = False',
            ),
            (
              key: 'CameraBoom → Enable Camera Lag',
              value: 'True  (Driven by $primaryTuningLabel)',
            ),
            (
              key: 'HudCanvas → Space',
              value: 'Screen  ·  Draw at Desired Size = True',
            ),
          ]);
        } else if (isUnity) {
          inspRows.addAll([
            (key: 'HudCanvas → Render Mode', value: 'Screen Space - Overlay'),
            (
              key: 'CanvasScaler → UI Scale Mode',
              value: 'Scale With Screen Size (1920 × 1080)',
            ),
            (
              key: 'CameraSmoothing Binding',
              value: primaryTuningLabel,
            ),
          ]);
        } else {
          inspRows.addAll([
            (key: 'FollowCamera → Enabled', value: 'On (Checked)'),
            (
              key: 'FollowCamera → Position Smoothing',
              value: 'Enabled  (Driven by $primaryTuningLabel)',
            ),
            (
              key: 'HudCanvas → Layer',
              value: '10 (Renders above world nodes)',
            ),
          ]);
        }
      } else if (hasWeaponSetup) {
        inspRows.addAll([
          (
            key: 'WeaponMesh → Collision',
            value: 'NoCollision (Visual Socket Only)',
          ),
          (
            key: 'InteractBox → Box Extent',
            value: 'X = 50.0, Y = 50.0, Z = 20.0',
          ),
          (key: 'Tuning Binding', value: primaryTuningLabel),
        ]);
      } else {
        if (isUnreal) {
          inspRows.addAll([
            (
              key: 'VisualMesh → Static Mesh',
              value: 'Shape_Plane / Shape_Cube',
            ),
            (
              key: 'InteractBox → Box Extent',
              value: 'X = 50.0, Y = 50.0, Z = 20.0',
            ),
            (
              key: 'Collision Presets',
              value: 'OverlapAllDynamic  (Generate Overlap Events = True)',
            ),
          ]);
        } else if (isUnity) {
          inspRows.addAll([
            (
              key: 'VisualMesh → Renderer',
              value: 'MeshRenderer / SpriteRenderer',
            ),
            (
              key: 'InteractTrigger → BoxCollider',
              value: 'Is Trigger = True (Checked)',
            ),
            (key: 'Tuning Parameter', value: primaryTuningLabel),
          ]);
        } else {
          inspRows.addAll([
            (key: 'Visual → Size / Texture', value: '64 × 64 px'),
            (
              key: 'CollisionShape2D → Shape',
              value: 'New RectangleShape2D (Extents: 32, 32)',
            ),
            (key: 'HitBox → Monitoring', value: 'On (Checked)'),
          ]);
        }
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
      // Runtime Logic / Event Graph / Guard Step
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
      codeWhere = stepPath;
      codeBody = rawCode;
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
          color: Colors.white.withValues(alpha: 0.015),
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
                  color: Colors.white.withValues(alpha: 0.03),
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
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                      baseStyle: GoogleFonts.jetBrainsMono(
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
                              ],
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

    final tokenKindByLiteral = <String, String>{};

    // 1. Tuning variable identifiers & full tuning specs -> 'tune' (Violet)
    for (final rawTune in tuningItems) {
      final trimmed = rawTune.trim();
      if (trimmed.isNotEmpty) {
        tokenKindByLiteral[trimmed] = 'tune';
        final varName = trimmed.split(':').first.trim();
        if (varName.length >= 3) {
          tokenKindByLiteral[varName] = 'tune';
        }
      }
    }

    // 2. Concrete guard variables, conditions & guard rules -> 'guard' (Amber)
    for (final guardToken
        in TaskHowToBlueprint.extractGuardHighlightTokens(edgeItems)) {
      tokenKindByLiteral[guardToken] = 'guard';
    }

    // 3. Concrete asset & component names -> 'asset' (Cyan)
    for (final m in _ReleaseWorkbenchScreenState._assetTokenRegex.allMatches(text)) {
      final matchStr = m.group(0)!;
      tokenKindByLiteral.putIfAbsent(matchStr, () => 'asset');
    }

    if (tokenKindByLiteral.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final sortedTokens = tokenKindByLiteral.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final pattern = sortedTokens.map(RegExp.escape).join('|');
    final combinedRegex = RegExp(pattern);

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
