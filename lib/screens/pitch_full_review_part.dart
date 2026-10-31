part of 'project_pitch_screen.dart';

extension _PitchFullReviewExt on _ProjectPitchScreenState {
  Widget _buildReleaseTrainPipeline(ProjectConceptBlueprint draft) {
    final firstReleaseTitle = draft.releaseTrainTitles.isNotEmpty
        ? draft.releaseTrainTitles.first
        : 'v0.1: ${draft.title} Core Loop - Prototype';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          padding: EdgeInsets.fromLTRB(isFirst ? 14 : 8, 10, 8, 10),
          decoration: BoxDecoration(
            border: Border(
              left: isFirst
                  ? BorderSide(color: accentAmber, width: 3)
                  : BorderSide.none,
              top: BorderSide(color: borderSubtle),
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Row(
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
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fullTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isFirst ? textPrimary : textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${draft.coreLoopBeats.length} Beats · ${draft.gameSpec.length} Specs · ✎',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: textSecondary.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Single-Page Complete Concept Blueprint (Open Borderless Architectural Sheet) ──
  Widget _buildFullReviewWorkspace(ProjectConceptBlueprint draft) {
    final intake = widget.workbench.sparkIntake;
    final expansionCards = intake?.expansionCards ?? const [];
    final isPrewarming = widget.workbench.isPrewarmingReleaseBlueprint;
    final isPrewarmed = widget.workbench.hasPrewarmedReleaseBlueprint;

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
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
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
                        if (isPrewarming || isPrewarmed)
                          Container(
                            key: const ValueKey('blueprint_prewarm_status_badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: (isPrewarmed ? accentEmerald : accentAmber)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: (isPrewarmed ? accentEmerald : accentAmber)
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              isPrewarmed
                                  ? '● v0.1 Outline Pre-Warmed'
                                  : '⟳ Pre-warming v0.1 Outline...',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isPrewarmed ? accentEmerald : accentAmber,
                              ),
                            ),
                          ),
                      ],
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
                      'Click any item to edit inline, or use 💬 Ask Agent on any section.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('new_spark_reset_btn'),
                      onPressed: () => widget.workbench.resetConceptToSpark(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textSecondary,
                        backgroundColor: bgRecessed,
                        side: BorderSide(color: borderSubtle),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        '+ New Project',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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
                    _buildPrimaryApproveButton(),
                  ],
                ),
              ],
            ),
          ),

          // Optional 1-Line Mechanic Twist Pill Bar (when Spark Expansion Cards exist)
          if (expansionCards.isNotEmpty)
            Container(
              key: const ValueKey('blueprint_twist_pills_bar'),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderSubtle)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '✦ ADD MECHANIC TWIST:',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: textMuted,
                    ),
                  ),
                  for (int i = 0; i < expansionCards.length; i++)
                    Builder(
                      builder: (context) {
                        final card = expansionCards[i];
                        final isSelected = card.isSelected;
                        return Tooltip(
                          message: card.description,
                          waitDuration: const Duration(milliseconds: 220),
                          child: InkWell(
                            key: ValueKey('blueprint_twist_pill_$i'),
                            onTap: widget.workbench.isAgentBusy
                                ? null
                                : () {
                                    widget.workbench.toggleSparkExpansionCard(i);
                                    widget.workbench.updateConceptDraft((d) {
                                      final beatEntry =
                                          '${card.title}: ${card.description}';
                                      if (card.isSelected) {
                                        if (!d.coreLoopBeats.any(
                                          (b) => b
                                              .toLowerCase()
                                              .startsWith(card.title.toLowerCase()),
                                        )) {
                                          d.coreLoopBeats = [
                                            ...d.coreLoopBeats,
                                            beatEntry,
                                          ];
                                        }
                                      } else {
                                        d.coreLoopBeats = d.coreLoopBeats
                                            .where(
                                              (b) => !b
                                                  .toLowerCase()
                                                  .startsWith(
                                                    card.title.toLowerCase(),
                                                  ),
                                            )
                                            .toList();
                                      }
                                    });
                                  },
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? accentEmerald.withValues(alpha: 0.14)
                                    : bgRecessed,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: isSelected
                                      ? accentEmerald.withValues(alpha: 0.7)
                                      : borderSubtle,
                                ),
                              ),
                              child: Text(
                                isSelected
                                    ? '✓ ${card.title}'
                                    : '+ ${card.title}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? accentEmerald
                                      : textSecondary,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),

          const SizedBox(height: 18),

          // Compact 2-Column Architectural Blueprint Grid (All 9 Sections Visible Together)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int idx = 0; idx < _sections.length; idx++) ...[
                      if (idx > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
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
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: borderSubtle,
                      ),
                    ),
                    _buildReleaseTrainPipeline(draft),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Row 1: 01 Goal (Left) | 08 Done When (Right)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 20),
                          child: _buildFullReviewBlock(
                            draft: draft,
                            sectionIdx: 0,
                            child: _buildSectionContentWidget(
                              draft,
                              0,
                              isReadOnlySummary: false,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.only(left: 20),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: borderSubtle),
                            ),
                          ),
                          child: _buildFullReviewBlock(
                            draft: draft,
                            sectionIdx: 7,
                            child: _buildSectionContentWidget(
                              draft,
                              7,
                              isReadOnlySummary: false,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Divider(height: 1, thickness: 1, color: borderSubtle),
                  ),

                  // Row 2: 02 Game Spec (Left) | 03 Tech Spec (Right)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 20),
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
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.only(left: 20),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: borderSubtle),
                            ),
                          ),
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
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Divider(height: 1, thickness: 1, color: borderSubtle),
                  ),

                  // Row 3: 06 Core Loop (Left) | 04 Design Pillars + 05 Trade-Offs + 07 Out of Scope (Right)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 11,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 20),
                          child: _buildFullReviewBlock(
                            draft: draft,
                            sectionIdx: 5,
                            child: _buildSectionContentWidget(
                              draft,
                              5,
                              isReadOnlySummary: false,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 10,
                        child: Container(
                          padding: const EdgeInsets.only(left: 20),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: borderSubtle),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildFullReviewBlock(
                                draft: draft,
                                sectionIdx: 3,
                                child: _buildSectionContentWidget(
                                  draft,
                                  3,
                                  isReadOnlySummary: false,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: borderSubtle,
                                ),
                              ),
                              _buildFullReviewBlock(
                                draft: draft,
                                sectionIdx: 4,
                                child: _buildSectionContentWidget(
                                  draft,
                                  4,
                                  isReadOnlySummary: false,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: borderSubtle,
                                ),
                              ),
                              _buildFullReviewBlock(
                                draft: draft,
                                sectionIdx: 6,
                                child: _buildSectionContentWidget(
                                  draft,
                                  6,
                                  isReadOnlySummary: false,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Divider(height: 1, thickness: 1, color: borderSubtle),
                  ),

                  // Row 4: 09 Release Train (v0.1)
                  _buildReleaseTrainPipeline(draft),
                ],
              );
            },
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
    final builtReleaseCount = widget.workbench.projectReleases
        .where((r) => r.childrenIds.isNotEmpty)
        .length;
    final canRebuildInitialV01 = showRebuildSecondary && builtReleaseCount <= 1;
    if (hasBuiltRelease) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canRebuildInitialV01) ...[
            Tooltip(
              message: 'Regenerate v0.1 Workbench from scratch',
              child: OutlinedButton(
                key: key == null
                    ? const ValueKey('rebuild_v01_from_concept_btn')
                    : null,
                onPressed: widget.workbench.isAgentBusy
                    ? null
                    : () => widget.workbench.approveConceptAndBuildRelease(
                          releaseId:
                              widget.workbench.projectReleases.firstOrNull?.id,
                        ),
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
                    if (sectionIdx != 1 && sectionIdx != 2 && options.isEmpty) ...[
                      Tooltip(
                        message:
                            'Generate AI preset options for ${sec.shortTitle}',
                        child: InkWell(
                          key: ValueKey(
                            'compact_shuffle_options_btn_$sectionIdx',
                          ),
                          onTap: widget.workbench.isAgentBusy
                              ? null
                              : () => widget.workbench
                                  .regenerateStage1SectionOptions(sec.optionKey),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: bgRecessed,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: borderSubtle),
                            ),
                            child: Text(
                              '✦ Presets ↻',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    OutlinedButton(
                      key: ValueKey('inline_agent_toggle_$sectionIdx'),
                      onPressed: () {
                        final willOpen = _inlineEditingSectionIdx != sectionIdx;
                        _rebuild(() {
                          if (!willOpen) {
                            _inlineEditingSectionIdx = null;
                          } else {
                            _inlineEditingSectionIdx = sectionIdx;
                            _inlineReviewPromptController.clear();
                          }
                        });
                        if (willOpen &&
                            _optionsForSection(draft, sectionIdx).isEmpty &&
                            !widget.workbench.isAgentBusy) {
                          widget.workbench.regenerateStage1SectionOptions(
                            sec.optionKey,
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            isInlineOpen ? focalAccentFg : textPrimary,
                        backgroundColor:
                            isInlineOpen ? focalAccent : bgRecessed,
                        side: BorderSide(color: borderBright),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
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
