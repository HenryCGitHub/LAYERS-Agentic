part of 'release_workbench_screen.dart';

extension _WorkbenchEngineAreasExt on _ReleaseWorkbenchScreenState {
  /// Synthesizes `.tscn` Scene Tree hierarchy lines for a `SCENE` Unified Step
  /// (never includes fake IDE Inspector chrome or `+ Add Node` controls).
  List<String> _synthesizeSceneTreeLines(
    TaskHowToSubStep subStep, {
    required ({String icon, String componentKey, String displayLabel})
        activeTargetComp,
    required String assetName,
  }) {
    final area1 = (subStep.area1Hierarchy ?? '').trim();
    final rawCode = subStep.codeFormula.trim();
    final source = area1.isNotEmpty
        ? area1
        : (RegExp(r'[└├]─(?!─►)').hasMatch(rawCode) ? rawCode : '');
    if (source.isNotEmpty) {
      final parsed = source
          .split('\n')
          .map((l) => l.trimRight())
          .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('//'))
          .toList();
      if (parsed.isNotEmpty) return parsed;
    }
    final rootLabel = assetName.replaceAll(RegExp(r'\.(tscn|gd)$'), '');
    final pascalRoot = rootLabel
        .split(RegExp(r'[_\s-]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join();
    return [
      '${pascalRoot.isNotEmpty ? pascalRoot : 'FeatureRoot'} (${activeTargetComp.componentKey})',
      '└─ CollisionShape2D/3D (Capsule / Shape)',
    ];
  }

  /// Extracts child node tuples `(name, type)` for `GodotVirtualFile.buildTscnStarterScaffold`.
  List<({String name, String type})> _buildSceneTscnChildren(
    List<String> sceneTreeLines, {
    required bool is2D,
  }) {
    final out = <({String name, String type})>[];
    for (int i = 1; i < sceneTreeLines.length; i++) {
      final cleaned = sceneTreeLines[i]
          .replaceAll(RegExp(r'^[└├│─\s•\-🎯📦⚙️📷🦴🧩📁⚡🗺]+'), '')
          .replaceAll('[ACTIVE]', '')
          .replaceAll('← SELECTED', '')
          .trim();
      if (cleaned.isEmpty) continue;
      final m = RegExp(r'^([A-Za-z0-9_]+)(?:\s*\(([^)]+)\))?').firstMatch(cleaned);
      if (m == null) continue;
      final name = m.group(1)!.trim();
      var type = (m.group(2) ?? '').trim();
      if (type.isEmpty || type.contains('/')) {
        if (name.toLowerCase().contains('collision')) {
          type = is2D ? 'CollisionShape2D' : 'CollisionShape3D';
        } else if (name.toLowerCase().contains('camera')) {
          type = is2D ? 'Camera2D' : 'Camera3D';
        } else if (name.toLowerCase().contains('timer')) {
          type = 'Timer';
        } else if (name.toLowerCase().contains('area')) {
          type = is2D ? 'Area2D' : 'Area3D';
        } else {
          type = is2D ? 'Node2D' : 'Node3D';
        }
      }
      out.add((name: name, type: type));
    }
    return out;
  }

  /// Builds a shared starter Godot 4 `.tscn` scaffold string from a feature's
  /// asset spec, Scene Tree lines, and attached script path.
  String _buildFeatureStarterTscnText({
    required String assetName,
    required String parentClassLabel,
    required bool is2D,
    required List<String> sceneTreeLines,
    required String? scriptResPath,
  }) {
    final cleanRoot = assetName.replaceAll(RegExp(r'\.(tscn|gd)$'), '');
    final pascalRoot = cleanRoot
        .split(RegExp(r'[_\s-]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join();
    final fallbackRootType = is2D ? 'CharacterBody2D' : 'CharacterBody3D';
    final rootType = GodotVirtualFile.sanitizeGdClassName(
      parentClassLabel,
      fallback: fallbackRootType,
    );
    final children = _buildSceneTscnChildren(sceneTreeLines, is2D: is2D);
    return GodotVirtualFile.buildTscnStarterScaffold(
      rootNodeName: pascalRoot.isNotEmpty ? pascalRoot : 'FeatureRoot',
      rootNodeType: rootType,
      scriptResPath: scriptResPath,
      childNodes: children,
    );
  }

  /// Synthesizes Markdown pipe-table rows (`| Node / Category | Property | Value |`)
  /// for `GodotInspectorPanel` from explicit pipe tables, `area2Inspector` hints,
  /// matching checkpoint `tuningParams`, and inline edits.
  List<String> _synthesizeInspectorTableLines({
    required FeatureStateNode node,
    required TaskHowToSubStep activeSubStep,
    required ({String icon, String componentKey, String displayLabel})
        activeTargetComp,
    required List<String> tuningItems,
    required bool is2D,
  }) {
    final rawCode = activeSubStep.codeFormula.trim();
    final rawLines = rawCode.isNotEmpty ? rawCode.split('\n') : const <String>[];
    final pipeLines = rawLines
        .where((l) => l.trim().startsWith('|') && l.trim().endsWith('|'))
        .toList();
    if (pipeLines.length >= 2) {
      if (activeSubStep.resolvedDockStage != GodotDockStage.inspector ||
          tuningItems.isEmpty) {
        return pipeLines;
      }
      final existingCorpus = pipeLines.join('\n').toLowerCase();
      final appendedRows = <String>[];
      for (final tp in tuningItems) {
        final parts =
            tp.split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex);
        final k = parts.first.trim();
        final v = parts.length > 1 ? parts.sublist(1).join(':').trim() : '1.0';
        if (k.isEmpty || v.isEmpty) continue;
        final inferred = _inferOwningComponentForProperty(
          rawKey: k,
          defaultComponentKey: activeTargetComp.componentKey,
          is2D: is2D,
        );
        final propLabel = inferred.propertyLabel.trim().isNotEmpty
            ? inferred.propertyLabel.trim()
            : k;
        if (existingCorpus.contains(k.toLowerCase()) ||
            existingCorpus.contains(propLabel.toLowerCase())) {
          continue;
        }
        final overrideVal =
            _customComponentPropertyOverrides['${node.id}::$k'] ??
                _customComponentPropertyOverrides['${node.id}::$propLabel'];
        final finalVal =
            (overrideVal != null && overrideVal.isNotEmpty) ? overrideVal : v;
        appendedRows.add('| ${inferred.categoryLabel} | $propLabel | $finalVal |');
      }
      return appendedRows.isEmpty ? pipeLines : [...pipeLines, ...appendedRows];
    }

    final convertedGraph = _tryConvertConfigGraphToTableLines(
      rawCode,
      stepDo: activeSubStep.instruction.trim(),
      stepRole: activeSubStep.stepRole ?? '',
      defaultTarget: activeTargetComp.displayLabel,
    );
    if (convertedGraph.length >= 2) return convertedGraph;

    final rows = <({String cat, String prop, String val})>[];
    final seenProps = <String>{};

    void addProp(String rawKey, String rawVal) {
      final k = rawKey.trim();
      final v = rawVal.trim();
      if (k.isEmpty || v.isEmpty) return;
      final inferred = _inferOwningComponentForProperty(
        rawKey: k,
        defaultComponentKey: activeTargetComp.componentKey,
        is2D: is2D,
      );
      final propLabel = inferred.propertyLabel.trim().isNotEmpty
          ? inferred.propertyLabel.trim()
          : k;
      final norm = propLabel.toLowerCase();
      if (!seenProps.add(norm)) return;
      final overrideVal =
          _customComponentPropertyOverrides['${node.id}::$k'] ??
              _customComponentPropertyOverrides['${node.id}::$propLabel'];
      rows.add((
        cat: inferred.categoryLabel,
        prop: propLabel,
        val: (overrideVal != null && overrideVal.isNotEmpty) ? overrideVal : v,
      ));
    }

    final aiArea2 = (activeSubStep.area2Inspector ?? '').trim();
    if (aiArea2.isNotEmpty) {
      final entries =
          aiArea2.contains('\n') ? aiArea2.split('\n') : aiArea2.split('|');
      for (final rawEntry in entries) {
        final clean = rawEntry.trim();
        if (clean.isEmpty) continue;
        final cIdx = clean.indexOf(':');
        final eIdx = clean.indexOf('=');
        final dIdx = cIdx != -1 ? cIdx : eIdx;
        if (dIdx > 0 && dIdx < clean.length - 1) {
          addProp(clean.substring(0, dIdx), clean.substring(dIdx + 1));
        }
      }
    }

    final dockStage = activeSubStep.resolvedDockStage;
    final corpus =
        '${activeSubStep.shortTitle} ${activeSubStep.instruction} $rawCode $aiArea2'
            .toLowerCase();
    for (final tp in tuningItems) {
      final parts =
          tp.split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex);
      final k = parts.first.trim();
      final v = parts.length > 1 ? parts.sublist(1).join(':').trim() : '1.0';
      if (k.isEmpty) continue;
      if (dockStage == GodotDockStage.inspector ||
          corpus.contains(k.toLowerCase())) {
        addProp(k, v);
      }
    }

    if (rows.isEmpty && dockStage == GodotDockStage.inspector) {
      for (final tp in tuningItems.take(4)) {
        final parts =
            tp.split(_ReleaseWorkbenchScreenState._tuningVarDelimiterRegex);
        final k = parts.first.trim();
        final v = parts.length > 1 ? parts.sublist(1).join(':').trim() : '1.0';
        if (k.isNotEmpty) addProp(k, v);
      }
    }

    if (rows.isEmpty) return const [];
    return [
      '| Node / Category | Property | Value |',
      '| --- | --- | --- |',
      for (final r in rows) '| ${r.cat} | ${r.prop} | ${r.val} |',
    ];
  }

  String _resolveEffectiveResPathForStep({
    required TierDocument feat,
    required FeatureStateNode node,
    required TaskHowToSubStep subStep,
  }) {
    final fromStep = widget.workbench.extractPrimaryScriptResPath(subStep.stepPath) ??
        widget.workbench.extractPrimarySceneResPath(subStep.stepPath);
    if (fromStep != null && fromStep.trim().isNotEmpty) {
      return GodotVirtualFile.normalizeResPath(fromStep);
    }
    final fromPrimary = widget.workbench.extractPrimaryScriptResPath(
          node.parameters['primarySharedScriptOrScene'] ??
              feat.sections['primary_asset'],
        ) ??
        widget.workbench.extractPrimarySceneResPath(
          node.parameters['primarySharedScriptOrScene'] ??
              feat.sections['primary_asset'],
        );
    if (fromPrimary != null && fromPrimary.trim().isNotEmpty) {
      return GodotVirtualFile.normalizeResPath(fromPrimary);
    }
    final derived = TaskHowToBlueprint.deriveConcreteAssetName(feat.title);
    final snake = derived.snakeName.isNotEmpty ? derived.snakeName : 'feature';
    return 'res://scripts/$snake.gd';
  }

  Widget _buildInitialSetupCard({
    required TierDocument feat,
    required FeatureStateNode node,
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
    if (!assetSpec.isNewAssetOnTask) {
      return SizedBox.shrink(key: ValueKey('initial_setup_area_${node.id}'));
    }
    final stepSummary = assetSpec.setupSteps
        .map((s) => s.label.trim())
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return Container(
      key: ValueKey('initial_setup_area_${node.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 5,
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
              InkWell(
                key: ValueKey('compact_shared_asset_badge_${node.id}'),
                borderRadius: BorderRadius.circular(4),
                onTap: () => showGodotFilesAndSyncDialog(
                  context,
                  widget.workbench,
                  initialResPath: widget.workbench
                          .extractPrimaryScriptResPath(
                        feat.sections['primary_asset'],
                      ) ??
                      widget.workbench.extractPrimarySceneResPath(
                        feat.sections['primary_asset'],
                      ),
                  activeFeature: feat,
                ),
                child: Text(
                  '${assetSpec.assetIcon} ${assetSpec.assetName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: fontBody,
                    fontWeight: weightBold,
                    color: const Color(0xFF38BDF8),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF131B28),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF243046)),
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
              if (stepSummary.isNotEmpty)
                Text(
                  stepSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: fontMicro,
                    color: const Color(0xFF64748B),
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
              border: Border.all(color: const Color(0xFF243046)),
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
    );
  }

  Widget _buildSceneStageDockPane({
    required FeatureStateNode node,
    required List<String> sceneTreeLines,
    required String assetName,
    required String parentClassLabel,
    required bool is2D,
    required String? scriptResPath,
  }) {
    return Container(
      key: ValueKey('scene_dock_tree_pane_${node.id}'),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF0D1422),
              border: Border(bottom: BorderSide(color: Color(0xFF1F2B3E))),
            ),
            child: Row(
              children: [
                Text(
                  '🌲 .tscn NODE TREE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF34D399),
                  ),
                ),
                const Spacer(),
                InkWell(
                  key: ValueKey('copy_starter_tscn_btn_${node.id}'),
                  borderRadius: BorderRadius.circular(5),
                  onTap: () {
                    final scaffold = _buildFeatureStarterTscnText(
                      assetName: assetName,
                      parentClassLabel: parentClassLabel,
                      is2D: is2D,
                      sceneTreeLines: sceneTreeLines,
                      scriptResPath: scriptResPath,
                    );
                    Clipboard.setData(ClipboardData(text: scaffold));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Copied starter $assetName hierarchy to clipboard ✓',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13221D),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFF34D399).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '⧉ Copy Starter .tscn',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6EE7B7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < sceneTreeLines.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == sceneTreeLines.length - 1 ? 0 : 4,
                    ),
                    child: Text(
                      sceneTreeLines[i],
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: fontBody,
                        fontWeight: i == 0 ? weightBold : weightRegular,
                        color: i == 0
                            ? const Color(0xFF34D399)
                            : const Color(0xFFE2E8F0),
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineCodeSyncStrip({
    required TierDocument feat,
    required FeatureStateNode node,
    required int stepIdx,
    required String resPath,
  }) {
    final normPath = GodotVirtualFile.normalizeResPath(resPath);
    final vf = widget.workbench.godotFileForResPath(normPath);
    final diffLines = vf != null
        ? widget.workbench.previewDiskDiffForResPath(normPath)
        : const <GodotDiffLine>[];
    final addedCount =
        diffLines.where((l) => l.kind == GodotDiffLineKind.added).length;
    final hasCloudFile = vf != null && vf.content.trim().isNotEmpty;
    final statusLabel = !hasCloudFile
        ? 'Cloud File: $normPath'
        : (addedCount > 0
            ? 'Patched in Cloud · $normPath (+$addedCount lines)'
            : 'In Sync · $normPath');

    return Container(
      key: ValueKey('inline_code_sync_strip_${node.id}_$stepIdx'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0A111D),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: (addedCount > 0
                  ? const Color(0xFF38BDF8)
                  : const Color(0xFF1F2B3E))
              .withValues(alpha: addedCount > 0 ? 0.45 : 1.0),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: addedCount > 0
                      ? const Color(0xFF38BDF8)
                      : (hasCloudFile
                          ? const Color(0xFF34D399)
                          : const Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: addedCount > 0
                        ? const Color(0xFF7DD3FC)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              InkWell(
                key: ValueKey('inline_open_code_file_btn_${node.id}'),
                borderRadius: BorderRadius.circular(5),
                onTap: () {
                  _rebuild(() {
                    _isCodeFileWorkspaceMode = true;
                    _selectedCodeFileResPath = normPath;
                    _isShowingStarterTscnInCodeMode = false;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131B2A),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFF26334D)),
                  ),
                  child: Text(
                    'Show Full .gd',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
              ),
              InkWell(
                key: ValueKey('inline_review_diff_btn_${node.id}'),
                borderRadius: BorderRadius.circular(5),
                onTap: () => showGodotFilesAndSyncDialog(
                  context,
                  widget.workbench,
                  initialResPath: normPath,
                  activeFeature: feat,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E293D),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    widget.workbench.isGodotFolderLinked
                        ? 'Review Diff → Write'
                        : 'Link Folder & Write',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF7DD3FC),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dedicated `F6 · PLAYTEST SIGN-OFF GATE` pane at the bottom of a Feature's Build Queue.
  Widget _buildPlaytestGateWorkspacePane({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required FeatureStateNode node,
    required List<TaskHowToSubStep> unifiedSteps,
    required List<String> edgeItems,
    required List<String> tuningItems,
  }) {
    final doneSteps = unifiedSteps.where((s) => s.subtask.completed).length;
    final totalSteps = unifiedSteps.length;
    final signedOffGuards = [
      for (int i = 0; i < edgeItems.length; i++)
        if (node.isGuardSignedOff(i, edgeItems[i])) i,
    ].length;
    final endGoal = node.playtestCondition;
    final activeVer = widget.workbench.activeReleaseVersionTag;
    final hasNextCp = states.any(
      (s) => s.id != node.id && s.releaseVersion == activeVer && !s.isCompleted,
    );

    return Container(
      key: ValueKey('playtest_gate_card_${node.id}'),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D131F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: node.isPlaytestPassed
              ? accentEmerald.withValues(alpha: 0.5)
              : const Color(0xFF34D399).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF062E24),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: const Color(0xFF34D399).withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      '▶ F6 · PLAYTEST SIGN-OFF GATE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: weightBold,
                        color: const Color(0xFF34D399),
                      ),
                    ),
                  ),
                  Text(
                    '$doneSteps/$totalSteps Build Steps Done',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: fontMicro,
                      fontWeight: weightSemi,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
              if (edgeItems.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D160B),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.38),
                    ),
                  ),
                  child: Text(
                    '$signedOffGuards/${edgeItems.length} Guards Checked',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: fontMicro,
                      fontWeight: weightBold,
                      color: const Color(0xFFFCD34D),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF080D16),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFF1B263B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✓ PLAYTEST END GOAL (RUN SCENE F6)',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: fontMicro,
                    fontWeight: weightBold,
                    letterSpacing: 0.5,
                    color: const Color(0xFF34D399),
                  ),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  _buildSemanticStepSpan(
                    text: endGoal,
                    baseStyle: GoogleFonts.inter(
                      fontSize: fontItem,
                      fontWeight: weightSemi,
                      height: 1.45,
                      color: textPrimary,
                    ),
                    tuningItems: tuningItems,
                    edgeItems: edgeItems,
                    isCodeBlock: false,
                  ),
                ),
              ],
            ),
          ),
          if (edgeItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'STATE & BOUNDARY GUARDS',
              style: GoogleFonts.jetBrainsMono(
                fontSize: fontMicro,
                fontWeight: weightBold,
                letterSpacing: 0.6,
                color: const Color(0xFFFBBF24),
              ),
            ),
            const SizedBox(height: 8),
            for (int gIdx = 0; gIdx < edgeItems.length; gIdx++)
              Builder(
                builder: (context) {
                  final rawGuard = edgeItems[gIdx];
                  final isChecked = node.isGuardSignedOff(gIdx, rawGuard);
                  final cleanGuard = rawGuard
                      .replaceFirst(
                        RegExp(
                          r'^\[(?:STATE|PLAYTEST)?\s*GUARD\]\s*',
                          caseSensitive: false,
                        ),
                        '',
                      )
                      .trim();
                  return InkWell(
                    key: ValueKey('playtest_guard_check_${node.id}_$gIdx'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      node.setGuardSignedOff(gIdx, rawGuard, !isChecked);
                      widget.workbench.updateFeatureStates(feat.id, states);
                      _rebuild();
                    },
                    child: Container(
                      margin: EdgeInsets.only(
                        bottom: gIdx == edgeItems.length - 1 ? 0 : 6,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isChecked
                            ? const Color(0xFF0A1F18)
                            : const Color(0xFF0B0E17),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isChecked
                              ? const Color(0xFF34D399).withValues(alpha: 0.4)
                              : const Color(0xFF1F2A3F),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 17,
                            height: 17,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isChecked
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF07090E),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isChecked
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.6),
                              ),
                            ),
                            child: Text(
                              isChecked ? '✓' : '',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: weightBold,
                                color: const Color(0xFF05101A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text.rich(
                              _buildSemanticStepSpan(
                                text: cleanGuard,
                                baseStyle: GoogleFonts.inter(
                                  fontSize: fontBody,
                                  fontWeight: weightRegular,
                                  color: isChecked
                                      ? textSecondary
                                      : const Color(0xFFFDE68A),
                                ),
                                tuningItems: tuningItems,
                                edgeItems: edgeItems,
                                isCodeBlock: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: ValueKey('playtest_gate_add_fix_btn_${node.id}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFBBF24),
                  side: BorderSide(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onPressed: () {
                  _rebuild(() {
                    _inlineBugDrawerNodeId = _inlineBugDrawerNodeId == node.id
                        ? null
                        : node.id;
                  });
                },
                icon: const Icon(Icons.bug_report_outlined, size: 15),
                label: Text(
                  '+ Add [FIX] Step / Paste Debugger Trace',
                  style: GoogleFonts.inter(
                    fontSize: fontBody,
                    fontWeight: weightSemi,
                  ),
                ),
              ),
              ElevatedButton.icon(
                key: ValueKey('playtest_gate_pass_btn_${node.id}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentEmerald,
                  foregroundColor: const Color(0xFF042117),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                onPressed: () =>
                    _passCheckpointPlaytestAndAdvance(feat, states, node),
                icon: const Icon(Icons.verified_rounded, size: 16),
                label: Text(
                  hasNextCp
                      ? '✓ Pass Playtest & Next Checkpoint'
                      : '✓ Pass Playtest & Complete Feature',
                  style: GoogleFonts.inter(
                    fontSize: fontBody,
                    fontWeight: weightBold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Renders the focused Active Unified Step Card (DO -> Copy -> Verify) matching
  /// the step's Godot dock stage (`SCENE`, `INSP`, `CODE`, `WIRE`, `FIX`).
  Widget _buildEngineStepAreasBox({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required FeatureStateNode node,
    required List<TaskHowToSubStep> unifiedSteps,
    required int activeStepIdx,
    required List<String> tuningItems,
    required List<String> edgeItems,
  }) {
    if (unifiedSteps.isEmpty) {
      return SizedBox(
        key: ValueKey('area3_script_setup_panel_${node.id}'),
      );
    }

    final safeIdx = activeStepIdx.clamp(0, unifiedSteps.length - 1);
    final activeSubStep = unifiedSteps[safeIdx];
    final dockStage = activeSubStep.resolvedDockStage;
    final activeTargetComp = _resolveStepTargetComponent(
      activeSubStep,
      featTitle: feat.title,
    );
    final assetSpec = _resolveFeatureAssetSpec(
      feat: feat,
      checkpointIndex: checkpointIndex,
      activeStepIdx: safeIdx,
      activeSubStep: activeSubStep,
      activeTargetComp: activeTargetComp,
    );

    final rawCode = activeSubStep.codeFormula.trim();
    final stepCodeLines =
        rawCode.isNotEmpty ? rawCode.split('\n') : const <String>[];
    final rawPipeTableLines = stepCodeLines
        .where((l) => l.trim().startsWith('|') && l.trim().endsWith('|'))
        .toList();
    final stepDoInstruction = activeSubStep.instruction.trim();
    final stepPathBadgeText = activeSubStep.stepPath.trim().isNotEmpty
        ? activeSubStep.stepPath.trim()
        : assetSpec.assetName;
    final stepVerifyText = activeSubStep.verifyResult.trim();
    final windowCtx = _resolveWindowContextForSubStep(
      activeSubStep,
      activeTargetLabel: activeTargetComp.displayLabel,
    );

    final List<String> sceneTreeLines = dockStage == GodotDockStage.scene &&
            !(windowCtx.label == 'MAIN SCENE (.tscn)' &&
                rawPipeTableLines.length >= 2)
        ? _synthesizeSceneTreeLines(
            activeSubStep,
            activeTargetComp: activeTargetComp,
            assetName: assetSpec.assetName,
          )
        : const [];

    final bool showInspectorSheet = dockStage == GodotDockStage.inspector ||
        (activeSubStep.area2Inspector ?? '').trim().isNotEmpty;
    final List<String> effectiveTableLines = showInspectorSheet
        ? _synthesizeInspectorTableLines(
            node: node,
            activeSubStep: activeSubStep,
            activeTargetComp: activeTargetComp,
            tuningItems: tuningItems,
            is2D: assetSpec.is2D,
          )
        : (rawPipeTableLines.length >= 2
            ? rawPipeTableLines
            : _tryConvertConfigGraphToTableLines(
                rawCode,
                stepDo: stepDoInstruction,
                stepRole: activeSubStep.stepRole ?? '',
                defaultTarget: activeTargetComp.displayLabel,
              ));

    final effectiveResPath = _resolveEffectiveResPathForStep(
      feat: feat,
      node: node,
      subStep: activeSubStep,
    );
    final scriptResPath = widget.workbench.extractPrimaryScriptResPath(
      node.parameters['primarySharedScriptOrScene'] ??
          feat.sections['primary_asset'],
    );
    final bool showInlineCloudSyncStrip =
        (dockStage == GodotDockStage.code || dockStage == GodotDockStage.fix) &&
            effectiveResPath.endsWith('.gd');

    final Widget initialSetupWidget = _buildInitialSetupCard(
      feat: feat,
      node: node,
      assetSpec: assetSpec,
      tuningItems: tuningItems,
      edgeItems: edgeItems,
    );

    String stepGuardChipText = '';
    if (edgeItems.isNotEmpty) {
      final bool mentionsGuardConcept = activeSubStep.isGuardStep ||
          RegExp(
            r'\b(?:guard|clamp|cooldown|null|is_valid|invalid|limit|prevent|cap)\b',
            caseSensitive: false,
          ).hasMatch(
            '${activeSubStep.shortTitle} $stepDoInstruction $rawCode',
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

    final bool isSubDone = activeSubStep.subtask.completed;
    final String stepTitle = activeSubStep.shortTitle.trim().isNotEmpty
        ? activeSubStep.shortTitle.trim()
        : activeSubStep.subtask.text;
    final bool showCode = sceneTreeLines.isNotEmpty ||
        effectiveTableLines.isNotEmpty ||
        stepCodeLines.isNotEmpty;

    return Padding(
      key: ValueKey('area3_script_setup_panel_${node.id}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          initialSetupWidget,

          // Step Target & Prompt Action Strip
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
                      border: Border.all(color: const Color(0xFF262E40)),
                    ),
                    child: Text(
                      'STEP ${safeIdx + 1}/${unifiedSteps.length}',
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
                      border: Border.all(color: const Color(0xFF262E40)),
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
                            text: '${assetSpec.assetIcon} ${assetSpec.assetName}',
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
                ],
              ),
              InkWell(
                key: ValueKey('copy_task_ai_prompt_btn_${node.id}'),
                onTap: () => _copyActiveFeaturePrompt(feat),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181E2C),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF262E40)),
                  ),
                  child: Text(
                    '✦ Copy Feature Prompt',
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
          const SizedBox(height: 10),

          // Focused Single Active Step Card
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141B29),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSubDone
                    ? accentEmerald.withValues(alpha: 0.45)
                    : const Color(0xFF38BDF8).withValues(alpha: 0.48),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  key: ValueKey('task_sheet_step_row_${node.id}_$safeIdx'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        key: ValueKey('toggle_step_mark_${node.id}_$safeIdx'),
                        onTap: () => _toggleHowToSubStepCompletion(
                          feat,
                          states,
                          node,
                          safeIdx,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSubDone
                                ? const Color(0xFF10B981)
                                : const Color(0xFF07090E),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSubDone
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF38BDF8),
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
                        width: 24,
                        child: Text(
                          (safeIdx + 1).toString().padLeft(2, '0'),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: fontBody,
                            fontWeight: weightBold,
                            color: const Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              stepTitle,
                              style: GoogleFonts.inter(
                                fontSize: fontItem,
                                fontWeight: weightBold,
                                color: const Color(0xFFF8FAFC),
                              ),
                            ),
                            Container(
                              key: ValueKey(
                                'window_context_badge_${node.id}_$safeIdx',
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    windowCtx.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color:
                                      windowCtx.accent.withValues(alpha: 0.36),
                                ),
                              ),
                              child: Text(
                                '${windowCtx.icon} ${windowCtx.label}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: windowCtx.accent,
                                ),
                              ),
                            ),
                            if (stepPathBadgeText.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF090D16),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                                child: Text(
                                  stepPathBadgeText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        key: ValueKey('edit_howto_substep_${node.id}_$safeIdx'),
                        borderRadius: BorderRadius.circular(5),
                        onTap: () => _promptEditHowToSubStepDialog(
                          feat,
                          states,
                          node,
                          safeIdx,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131B2A),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: const Color(0xFF24324B)),
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
                      const SizedBox(width: 5),
                      InkWell(
                        key: ValueKey('copy_howto_code_${node.id}_$safeIdx'),
                        onTap: () => _copySubStepCodeFormula(
                          safeIdx,
                          activeSubStep.codeFormula,
                        ),
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF162032),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: const Color(0xFF283854)),
                          ),
                          child: Text(
                            dockStage == GodotDockStage.scene
                                ? '⧉ Copy tree'
                                : '⧉ Copy code',
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
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF07090E),
                    border: Border(
                      top: BorderSide(color: Color(0xFF182234)),
                    ),
                  ),
                  child: _buildStepDrawerBody(
                    feat: feat,
                    states: states,
                    node: node,
                    stepIdx: safeIdx,
                    subStep: activeSubStep,
                    windowCtx: windowCtx,
                    showCode: showCode,
                    isDark: isDark,
                    stepDoInstruction: stepDoInstruction,
                    stepGuardChipText: stepGuardChipText,
                    sceneTreeLines: sceneTreeLines,
                    effectiveTableLines: effectiveTableLines,
                    stepCodeLines: stepCodeLines,
                    stepPathBadgeText: stepPathBadgeText,
                    stepVerifyText: stepVerifyText,
                    assetName: assetSpec.assetName,
                    parentClassLabel: assetSpec.parentClassLabel,
                    is2D: assetSpec.is2D,
                    scriptResPath: scriptResPath,
                    effectiveResPath: effectiveResPath,
                    showInlineCloudSyncStrip: showInlineCloudSyncStrip,
                    tuningItems: tuningItems,
                    edgeItems: edgeItems,
                    fontMicro: fontMicro,
                    fontBody: fontBody,
                    weightRegular: weightRegular,
                    weightSemi: weightSemi,
                    weightBold: weightBold,
                    textPrimary: textPrimary,
                    onInspectorPropertyChanged: (propKey, newVal) =>
                        _saveInlineTuningParam(
                      feat: feat,
                      states: states,
                      node: node,
                      activeStepIdx: safeIdx,
                      rawValue: '$propKey: $newVal',
                      propertyKey: propKey,
                    ),
                  ),
                ),
              ],
            ),
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
      final tokenKind = tokenKindByLiteral[matchedText];
      final tokenColor = switch (tokenKind) {
        'tune' => accentViolet,
        'guard' => accentAmber,
        _ => accentCyan,
      };
      spans.add(
        TextSpan(
          text: matchedText,
          style: GoogleFonts.jetBrainsMono(
            fontSize: monoSize,
            fontWeight: isCodeBlock ? weightRegular : weightSemi,
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

  Widget _buildStepDrawerBody({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required FeatureStateNode node,
    required int stepIdx,
    required TaskHowToSubStep subStep,
    required ({String icon, String label, Color accent}) windowCtx,
    required bool showCode,
    required bool isDark,
    required String stepDoInstruction,
    required String stepGuardChipText,
    required List<String> sceneTreeLines,
    required List<String> effectiveTableLines,
    required List<String> stepCodeLines,
    required String stepPathBadgeText,
    required String stepVerifyText,
    required String assetName,
    required String parentClassLabel,
    required bool is2D,
    required String? scriptResPath,
    required String effectiveResPath,
    required bool showInlineCloudSyncStrip,
    required List<String> tuningItems,
    required List<String> edgeItems,
    required double fontMicro,
    required double fontBody,
    required FontWeight weightRegular,
    required FontWeight weightSemi,
    required FontWeight weightBold,
    required Color textPrimary,
    void Function(String propertyKey, String newValue)?
        onInspectorPropertyChanged,
  }) {
    final doItems = _parseDoActionItems(stepDoInstruction);
    final Widget? doWidget = doItems.isNotEmpty
        ? _buildVerticalDoList(
            nodeId: node.id,
            stepIdx: stepIdx,
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
              key: ValueKey('step_guard_pill_${node.id}_$stepIdx'),
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
            nodeId: node.id,
            stepIdx: stepIdx,
            subStep: subStep,
            stepVerifyText: stepVerifyText,
            tuningItems: tuningItems,
            edgeItems: edgeItems,
            fontMicro: fontMicro,
            weightRegular: weightRegular,
            weightBold: weightBold,
            onToggleChecked: () => _toggleHowToSubStepCompletion(
              feat,
              states,
              node,
              stepIdx,
            ),
          )
        : null;

    final Widget? rightVisual = showCode
        ? _buildStepRightVisualPane(
            feat: feat,
            node: node,
            stepIdx: stepIdx,
            isDark: isDark,
            sceneTreeLines: sceneTreeLines,
            effectiveTableLines: effectiveTableLines,
            stepCodeLines: stepCodeLines,
            stepPathBadgeText: stepPathBadgeText,
            windowCtx: windowCtx,
            assetName: assetName,
            parentClassLabel: parentClassLabel,
            is2D: is2D,
            scriptResPath: scriptResPath,
            effectiveResPath: effectiveResPath,
            showInlineCloudSyncStrip: showInlineCloudSyncStrip,
            tuningItems: tuningItems,
            edgeItems: edgeItems,
            fontMicro: fontMicro,
            fontBody: fontBody,
            weightRegular: weightRegular,
            textPrimary: textPrimary,
            onInspectorPropertyChanged: onInspectorPropertyChanged,
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
    required int stepIdx,
    required List<String> items,
    required List<String> tuningItems,
    required List<String> edgeItems,
    required double fontMicro,
    required double fontBody,
    required FontWeight weightRegular,
    required FontWeight weightBold,
  }) {
    return Container(
      key: ValueKey('step_do_instruction_${nodeId}_$stepIdx'),
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
                final rowKey = '${nodeId}_${stepIdx}_$i';
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
    required int stepIdx,
    required TaskHowToSubStep subStep,
    required String stepVerifyText,
    required List<String> tuningItems,
    required List<String> edgeItems,
    required double fontMicro,
    required FontWeight weightRegular,
    required FontWeight weightBold,
    required VoidCallback onToggleChecked,
  }) {
    final isDone = subStep.subtask.completed;
    return Container(
      key: ValueKey('step_check_footer_${nodeId}_$stepIdx'),
      padding: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF141D2E)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
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
          ),
          const SizedBox(width: 8),
          InkWell(
            key: ValueKey('step_check_toggle_btn_${nodeId}_$stepIdx'),
            borderRadius: BorderRadius.circular(5),
            onTap: onToggleChecked,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: isDone
                    ? const Color(0xFF10B981).withValues(alpha: 0.14)
                    : const Color(0xFF111827),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isDone
                      ? const Color(0xFF34D399).withValues(alpha: 0.48)
                      : const Color(0xFF26334D),
                ),
              ),
              child: Text(
                isDone ? '✓ Checked' : 'Mark Checked',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: weightBold,
                  color: isDone
                      ? const Color(0xFF6EE7B7)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildStepRightVisualPane({
    required TierDocument feat,
    required FeatureStateNode node,
    required int stepIdx,
    required bool isDark,
    required List<String> sceneTreeLines,
    required List<String> effectiveTableLines,
    required List<String> stepCodeLines,
    required String stepPathBadgeText,
    required ({String icon, String label, Color accent}) windowCtx,
    required String assetName,
    required String parentClassLabel,
    required bool is2D,
    required String? scriptResPath,
    required String effectiveResPath,
    required bool showInlineCloudSyncStrip,
    required List<String> tuningItems,
    required List<String> edgeItems,
    required double fontMicro,
    required double fontBody,
    required FontWeight weightRegular,
    required Color textPrimary,
    void Function(String propertyKey, String newValue)?
        onInspectorPropertyChanged,
  }) {
    if (sceneTreeLines.isNotEmpty && effectiveTableLines.length >= 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSceneStageDockPane(
            node: node,
            sceneTreeLines: sceneTreeLines,
            assetName: assetName,
            parentClassLabel: parentClassLabel,
            is2D: is2D,
            scriptResPath: scriptResPath,
          ),
          const SizedBox(height: 10),
          _buildLevelPlacementTable(
            effectiveTableLines,
            isDark: isDark,
            stepPath: stepPathBadgeText,
            assetName: assetName,
            parentClassLabel: parentClassLabel,
            isLevelScene: windowCtx.label == 'MAIN SCENE (.tscn)',
            isInputMap: windowCtx.label == 'INPUT MAP',
            onPropertyChanged: onInspectorPropertyChanged,
          ),
        ],
      );
    }
    if (sceneTreeLines.isNotEmpty) {
      return _buildSceneStageDockPane(
        node: node,
        sceneTreeLines: sceneTreeLines,
        assetName: assetName,
        parentClassLabel: parentClassLabel,
        is2D: is2D,
        scriptResPath: scriptResPath,
      );
    }
    if (effectiveTableLines.length >= 2) {
      return _buildLevelPlacementTable(
        effectiveTableLines,
        isDark: isDark,
        stepPath: stepPathBadgeText,
        assetName: assetName,
        parentClassLabel: parentClassLabel,
        isLevelScene: windowCtx.label == 'MAIN SCENE (.tscn)',
        isInputMap: windowCtx.label == 'INPUT MAP',
        onPropertyChanged: onInspectorPropertyChanged,
      );
    }
    if (stepCodeLines.isNotEmpty) {
      final codeCard = _buildStepCodeLinesPane(
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
      if (!showInlineCloudSyncStrip) return codeCard;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          codeCard,
          _buildInlineCodeSyncStrip(
            feat: feat,
            node: node,
            stepIdx: stepIdx,
            resPath: effectiveResPath,
          ),
        ],
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
      dockStage: subStep.resolvedDockStage,
      isRenderedAsInspectorTable: tableLines.length >= 2,
      isRenderedAsSignalGraph: isEffectiveSignalGraph,
    );
  }

  ({String icon, String label, Color accent}) _resolveWindowContextBadge({
    required String stepPath,
    required String instruction,
    required String codeFormula,
    String stepRole = '',
    GodotDockStage? dockStage,
    bool isRenderedAsInspectorTable = false,
    bool isRenderedAsSignalGraph = false,
  }) {
    if (dockStage == GodotDockStage.fix || stepRole == 'fix') {
      return (
        icon: '🛠',
        label: 'FIX PATCH (.gd)',
        accent: const Color(0xFFF59E0B),
      );
    }
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
        icon: '⌨',
        label: 'INPUT MAP',
        accent: const Color(0xFFA78BFA),
      );
    }
    final isPipeTable = codeFormula
            .split('\n')
            .where((l) => l.trim().startsWith('|') && l.trim().endsWith('|'))
            .length >=
        2;
    final bool isInspectorNodeSetup = dockStage == GodotDockStage.inspector ||
        lowerPath.contains('inspector') ||
        lowerPath.contains('property') ||
        stepRole == 'inspector_setup';
    if (lowerPath.contains('main scene') ||
        lowerPath.contains('level scene') ||
        lowerPath.contains('instantiate child scene') ||
        lowerInstr.contains('spawnpoint') ||
        lowerInstr.contains('instantiate child scene') ||
        (lowerPath.contains('scene tree') &&
            (lowerInstr.contains('instantiate') ||
                lowerInstr.contains('main'))) ||
        (isPipeTable && !isInspectorNodeSetup && dockStage != GodotDockStage.inspector)) {
      return (
        icon: '🗺',
        label: 'MAIN SCENE (.tscn)',
        accent: const Color(0xFF10B981),
      );
    }
    if (dockStage == GodotDockStage.scene ||
        (!isInspectorNodeSetup &&
            (lowerPath.contains('scene dock') ||
                lowerPath.contains('scene tree') ||
                lowerPath.contains('add child node') ||
                stepRole == 'editor_setup'))) {
      return (
        icon: '🌲',
        label: 'SCENE (.tscn)',
        accent: const Color(0xFF34D399),
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
        isInspectorNodeSetup ||
        (stepRole == 'editor_setup' && !looksLikeCppFile && !looksLikeGdScript)) {
      return (
        icon: '🎛',
        label: 'PROPERTY & LAYER SHEET',
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
    if ((dockStage == GodotDockStage.wire || stepRole == 'wire_and_verify') &&
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
    void Function(String propertyKey, String newValue)? onPropertyChanged,
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
      contract: widget.workbench.activeGodotContract,
      onPropertyChanged: onPropertyChanged,
    );
  }
}
