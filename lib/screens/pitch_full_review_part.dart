part of 'project_pitch_screen.dart';

extension _PitchFullReviewExt on _ProjectPitchScreenState {
  Widget _buildReleaseTrainPipeline(ProjectConceptBlueprint draft) {
    final firstReleaseTitle = draft.releaseTrainTitles.isNotEmpty
        ? draft.releaseTrainTitles.first
        : 'v0.1: ${draft.title} Core Loop - Prototype';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderSubtle)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'INITIAL RELEASE TARGET (v0.1)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                ),
              ),
              Text(
                'ACTIVE TARGET · v0.1',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: accentCyan,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Approving this Concept builds v0.1 in the Workbench. Future releases (v0.2+) are never queued ahead of time—once v0.1 is 100% complete, the Progressive Release Planner unlocks to help you decide what to upgrade and add next.',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        if (_activeInlineEditKey == 'release_train_0')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _buildInlineEditorBox(
              editKey: 'release_train_0',
              hintText: 'Edit Release v0.1 scope...',
              onSave: (val) => widget.workbench.updateConceptDraft((d) {
                final next = List<String>.from(d.releaseTrainTitles);
                if (next.isEmpty) {
                  next.add(val);
                } else {
                  next[0] = val;
                }
                d.releaseTrainTitles = next;
              }),
            ),
          )
        else
          _buildReleaseStepCard(
            firstReleaseTitle,
            draft: draft,
            isFirst: true,
            index: 0,
            onTap: () => _startInlineEdit('release_train_0', firstReleaseTitle),
          ),
      ],
    );
  }

  Widget _buildReleaseStepCard(
    String fullTitle, {
    required ProjectConceptBlueprint draft,
    required bool isFirst,
    required int index,
    VoidCallback? onTap,
  }) {
    final verTag = isFirst ? 'v0.1 · ACTIVE TARGET' : 'v0.${index + 1} · QUEUED';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('stage1_release_train_card_$index'),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(isFirst ? 14 : 8, 12, 8, 12),
          decoration: BoxDecoration(
            border: Border(
              left: isFirst
                  ? BorderSide(color: accentAmber, width: 3)
                  : BorderSide.none,
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    verTag,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isFirst
                          ? accentAmber
                          : textSecondary.withValues(alpha: 0.85),
                    ),
                  ),
                  Text(
                    isFirst ? 'READY TO PLAN →' : 'QUEUED',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: isFirst ? accentAmber : textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                fullTitle,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isFirst ? textPrimary : textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Builder(
                builder: (context) {
                  final totalBeats = draft.coreLoopBeats.length;
                  final isSplitTrain = draft.releaseTrainTitles.length > 1;
                  final halfCount = (totalBeats + 1) ~/ 2;
                  final scopeCaption = isSplitTrain
                      ? (index == 0
                          ? 'Part 1 Scope: Core Loop Beats 1–$halfCount (Controls & Primary Mechanics)'
                          : 'Part 2 Scope: Core Loop Beats ${halfCount + 1}–$totalBeats (Progression & Loop Reset)')
                      : 'Scope: $totalBeats Core Loop Beats · ${draft.gameSpec.length} Game Specs · ${draft.designPillars.length} Design Pillars';
                  return Text(
                    scopeCaption,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: textSecondary.withValues(alpha: 0.85),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step `10 · Full Review`: Boxless Single Editorial Dossier Sheet ──────────
  Widget _buildFullReviewWorkspace(ProjectConceptBlueprint draft) {
    return Container(
      key: const ValueKey('project_blueprint_card'),
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Verification Header (Open Hairline Divider, No Outer Box)
          Container(
            padding: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderSubtle)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 12,
              spacing: 16,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STEP 09 · FINAL BLUEPRINT VERIFICATION',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: accentAmber,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_activeInlineEditKey == 'blueprint_project_title')
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: _buildInlineEditorBox(
                          editKey: 'blueprint_project_title',
                          hintText: 'Project title...',
                          onSave: _saveInlineProjectTitle,
                        ),
                      )
                    else
                      InkWell(
                        key: const ValueKey('stage1_blueprint_title_inline_trigger'),
                        onTap: () => _promptEditProjectTitle(
                          draft,
                          key: 'blueprint_project_title',
                        ),
                        borderRadius: BorderRadius.circular(4),
                        child: Text(
                          '${draft.title} — Complete Project Concept Blueprint',
                          style: AppTheme.displayFont(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      'Hover any section to adjust it inline with the Agent, or click any item to edit directly.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _copyBlueprintAsMarkdown(draft),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: Text(
                        'Copy Markdown',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textPrimary,
                        backgroundColor: bgRecessed,
                        side: BorderSide(color: borderSubtle),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildPrimaryApproveButton(),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Open Editorial Sections (Hairline Dividers Only — No Outer Box)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 01 Goal (Full Width)
              _buildFullReviewBlock(
                draft: draft,
                sectionIdx: 0,
                child: _buildSectionContentWidget(
                  draft,
                  0,
                  isReadOnlySummary: false,
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Divider(height: 1, thickness: 1, color: borderSubtle),
              ),

              // 02 Game Spec + 03 Tech Spec (50/50 Side-by-Side Row with Equal Height)
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 720) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFullReviewBlock(
                          draft: draft,
                          sectionIdx: 1,
                          child: _buildSectionContentWidget(
                            draft,
                            1,
                            isReadOnlySummary: false,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: borderSubtle,
                          ),
                        ),
                        _buildFullReviewBlock(
                          draft: draft,
                          sectionIdx: 2,
                          child: _buildSectionContentWidget(
                            draft,
                            2,
                            isReadOnlySummary: false,
                          ),
                        ),
                      ],
                    );
                  }
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildFullReviewBlock(
                            draft: draft,
                            sectionIdx: 1,
                            child: _buildSectionContentWidget(
                              draft,
                              1,
                              isReadOnlySummary: false,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: borderSubtle,
                          ),
                        ),
                        Expanded(
                          child: _buildFullReviewBlock(
                            draft: draft,
                            sectionIdx: 2,
                            child: _buildSectionContentWidget(
                              draft,
                              2,
                              isReadOnlySummary: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // 04 Design Pillars through 08 Done When
              for (int idx = 3; idx < _sections.length; idx++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: borderSubtle,
                  ),
                ),
                _buildFullReviewBlock(
                  draft: draft,
                  sectionIdx: idx,
                  child: _buildSectionContentWidget(
                    draft,
                    idx,
                    isReadOnlySummary: false,
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: borderSubtle,
                ),
              ),
              _buildReleaseTrainPipeline(draft),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryApproveButton({
    Key? key,
    bool showRebuildSecondary = true,
  }) {
    final hasBuiltRelease = widget.workbench.activeReleaseBeats.isNotEmpty;
    if (hasBuiltRelease) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showRebuildSecondary) ...[
            Tooltip(
              message: 'Regenerate v0.1 Workbench from scratch',
              child: OutlinedButton(
                key: key == null
                    ? const ValueKey('rebuild_v01_from_concept_btn')
                    : null,
                onPressed: widget.workbench.isAgentBusy
                    ? null
                    : () => widget.workbench.approveConceptAndBuildRelease(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentAmber,
                  backgroundColor: bgRecessed,
                  side: BorderSide(color: accentAmber.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text(
                  '↻ Rebuild v0.1',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ElevatedButton(
            key: key ?? const ValueKey('return_to_workbench_btn'),
            onPressed: widget.workbench.isAgentBusy
                ? null
                : () => widget.workbench.setStage(WorkbenchStage.releaseWorkbench),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentEmerald,
              foregroundColor: Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: accentEmerald.withValues(alpha: 0.7)),
              ),
            ),
            child: Text(
              '✓ Return to Workbench →',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    }

    return ElevatedButton(
      key: key,
      onPressed: widget.workbench.isAgentBusy
          ? null
          : () => widget.workbench.approveConceptAndBuildRelease(),
      style: ElevatedButton.styleFrom(
        backgroundColor: focalAccent,
        foregroundColor: focalAccentFg,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: accentAmber.withValues(alpha: 0.55)),
        ),
      ),
      child: Text(
        widget.workbench.isAgentBusy
            ? 'Building v0.1 Workbench...'
            : 'Approve & Build v0.1 →',
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildFullReviewBlock({
    required ProjectConceptBlueprint draft,
    required int sectionIdx,
    required Widget child,
  }) {
    final sec = _sections[sectionIdx];
    final isInlineOpen = _inlineEditingSectionIdx == sectionIdx;
    final options = _optionsForSection(draft, sectionIdx);
    final showCompactPills = sectionIdx != 1 && sectionIdx != 2 && options.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => _rebuild(() => _hoveredReviewSectionIdx = sectionIdx),
      onExit: (_) {
        if (_hoveredReviewSectionIdx == sectionIdx) {
          _rebuild(() => _hoveredReviewSectionIdx = null);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isInlineOpen
              ? bgRecessed.withValues(alpha: 0.65)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: bgRecessed,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: borderBright),
                        ),
                        child: Text(
                          sec.numLabel,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          sec.title.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      key: ValueKey('inline_agent_toggle_$sectionIdx'),
                      onPressed: () {
                        _rebuild(() {
                          if (_inlineEditingSectionIdx == sectionIdx) {
                            _inlineEditingSectionIdx = null;
                          } else {
                            _inlineEditingSectionIdx = sectionIdx;
                            _inlineReviewPromptController.clear();
                          }
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isInlineOpen ? focalAccentFg : textPrimary,
                        backgroundColor: isInlineOpen ? focalAccent : bgRecessed,
                        side: BorderSide(color: borderBright),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        minimumSize: const Size(0, 26),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: Text(
                        isInlineOpen ? 'Close Agent' : '💬 Ask Agent',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: () => _goToStep(sectionIdx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textSecondary,
                        backgroundColor: bgRecessed,
                        side: BorderSide(color: borderSubtle),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        minimumSize: const Size(0, 26),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: Text(
                        'Focus →',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,

            // Compact 28px 1-Line AI Quick-Toggle / Preset Pills (Space-Saving Replacement for Tall Cards)
            if (showCompactPills) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    sec.isMultiSelect ? '✦ Quick Add:' : '✦ Presets:',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: textMuted,
                    ),
                  ),
                  for (int optIdx = 0; optIdx < options.length; optIdx++)
                    Builder(
                      builder: (context) {
                        final rawOpt = options[optIdx];
                        final split = _splitOptionIntoCardTitleAndBody(
                          rawOpt,
                          sectionIdx,
                          optIdx,
                        );
                        final isSelected = _isSectionOptionSelected(
                          sectionIdx,
                          optIdx,
                        );
                        final activeColor = sec.isMultiSelect
                            ? accentEmerald
                            : accentCyan;
                        final pillLabel = sec.isMultiSelect
                            ? (isSelected
                                ? '✓ ${split.title}'
                                : '+ ${split.title}')
                            : (isSelected
                                ? '● ${split.title}'
                                : '✦ ${split.title}');
                        return Tooltip(
                          message: rawOpt,
                          waitDuration: const Duration(milliseconds: 220),
                          child: InkWell(
                            key: ValueKey(
                              'compact_option_pill_${sectionIdx}_$optIdx',
                            ),
                            onTap: widget.workbench.isAgentBusy
                                ? null
                                : () => _selectSectionOption(
                                      draft,
                                      sectionIdx,
                                      optIdx,
                                    ),
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? activeColor.withValues(alpha: 0.14)
                                    : bgRecessed,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: isSelected
                                      ? activeColor.withValues(alpha: 0.7)
                                      : borderSubtle,
                                ),
                              ),
                              child: Text(
                                pillLabel,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? activeColor
                                      : textSecondary,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  Tooltip(
                    message: 'Generate fresh AI options for ${sec.shortTitle}',
                    child: InkWell(
                      key: ValueKey('compact_shuffle_options_btn_$sectionIdx'),
                      onTap: widget.workbench.isAgentBusy
                          ? null
                          : () => widget.workbench.regenerateStage1SectionOptions(
                                sec.optionKey,
                              ),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: bgRecessed,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: borderSubtle),
                        ),
                        child: Text(
                          '↻',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: accentCyan,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Contextual Inline Agent Drawer (Adjust section right inside Full Review without losing context)
            if (isInlineOpen) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bgRecessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderBright),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: bgSurface,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: borderSubtle),
                            ),
                            child: TextField(
                              controller: _inlineReviewPromptController,
                              autofocus: true,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Tell the Agent how to adjust ${sec.numLabel} ${sec.title}...',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                              onSubmitted: (_) => _submitSectionPrompt(
                                draft,
                                sectionIdx,
                                controller: _inlineReviewPromptController,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: widget.workbench.isAgentBusy
                              ? null
                              : () => _submitSectionPrompt(
                                    draft,
                                    sectionIdx,
                                    controller: _inlineReviewPromptController,
                                  ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: focalAccent,
                            foregroundColor: focalAccentFg,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          child: Text(
                            widget.workbench.isAgentBusy ? 'Updating...' : 'Apply',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (int optIdx = 0;
                            optIdx < _optionsForSection(draft, sectionIdx).length;
                            optIdx++)
                          InkWell(
                            onTap: () => _selectSectionOption(draft, sectionIdx, optIdx),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: bgSurface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _isSectionOptionSelected(sectionIdx, optIdx)
                                      ? (_sections[sectionIdx].isMultiSelect
                                          ? accentEmerald
                                          : textPrimary)
                                      : borderSubtle,
                                ),
                              ),
                              child: Text(
                                _optionsForSection(draft, sectionIdx)[optIdx],
                                style: GoogleFonts.inter(
                                  fontSize: 11,
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
            ],
          ],
        ),
      ),
    );
  }
}
