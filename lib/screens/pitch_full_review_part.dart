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
            padding: const EdgeInsets.symmetric(vertical: 4),
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
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bgRecessed,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderSubtle),
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
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: isFirst
                          ? accentAmber
                          : textSecondary.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${draft.coreLoopBeats.length} Epics · ${draft.gameSpec.length} Specs · ✎',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                fullTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isFirst ? textPrimary : textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Option 2 Enhanced: Spaced 3×3 Bento Concept Board ─────────────────────
  Widget _buildFullReviewWorkspace(ProjectConceptBlueprint draft) {
    final intake = widget.workbench.sparkIntake;
    final expansionCards = intake?.expansionCards ?? const [];

    Widget bentoSection(int idx) => _buildFullReviewBlock(
          draft: draft,
          sectionIdx: idx,
          child: _buildSectionContentWidget(
            draft,
            idx,
            isReadOnlySummary: false,
          ),
        );

    final launchpadCard = _buildBentoLaunchpadCard(draft);

    return Container(
      key: const ValueKey('project_blueprint_card'),
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Single Streamlined Header Bar (Project Title + Inline Twist Pills + Quiet Actions)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: bgBase.withValues(alpha: 0.6),
              border: Border(bottom: BorderSide(color: borderSubtle)),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              spacing: 12,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_activeInlineEditKey == 'blueprint_project_title')
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                draft.title,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.displayFont(
                                  fontSize: 18.5,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '✎',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (expansionCards.isNotEmpty)
                      Container(
                        key: const ValueKey('blueprint_twist_pills_bar'),
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          border: Border(left: BorderSide(color: borderSubtle)),
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '✦ TWISTS:',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
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
                                    waitDuration:
                                        const Duration(milliseconds: 220),
                                    child: InkWell(
                                      key: ValueKey('blueprint_twist_pill_$i'),
                                      onTap: widget.workbench.isAgentBusy
                                          ? null
                                          : () {
                                              widget.workbench
                                                  .toggleSparkExpansionCard(i);
                                              widget.workbench
                                                  .updateConceptDraft((d) {
                                                final beatEntry =
                                                    '${card.title}: ${card.description}';
                                                if (card.isSelected) {
                                                  if (!d.coreLoopBeats.any(
                                                    (b) => b
                                                        .toLowerCase()
                                                        .startsWith(
                                                          card.title
                                                              .toLowerCase(),
                                                        ),
                                                  )) {
                                                    d.coreLoopBeats = [
                                                      ...d.coreLoopBeats,
                                                      beatEntry,
                                                    ];
                                                  }
                                                } else {
                                                  d.coreLoopBeats =
                                                      d.coreLoopBeats
                                                          .where(
                                                            (b) => !b
                                                                .toLowerCase()
                                                                .startsWith(
                                                                  card.title
                                                                      .toLowerCase(),
                                                                ),
                                                          )
                                                          .toList();
                                                }
                                              });
                                            },
                                      borderRadius: BorderRadius.circular(99),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? accentEmerald.withValues(
                                                  alpha: 0.12,
                                                )
                                              : bgSurface,
                                          borderRadius:
                                              BorderRadius.circular(99),
                                          border: Border.all(
                                            color: isSelected
                                                ? accentEmerald.withValues(
                                                    alpha: 0.55,
                                                  )
                                                : borderSubtle,
                                          ),
                                        ),
                                        child: Text(
                                          isSelected
                                              ? '✓ ${card.title}'
                                              : '+ ${card.title}',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 9.5,
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
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('new_spark_reset_btn'),
                      onPressed: () => widget.workbench.resetConceptToSpark(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textSecondary,
                        backgroundColor: bgSurface,
                        side: BorderSide(color: borderSubtle),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 10,
                        ),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        '+ New Project',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copyBlueprintAsMarkdown(draft),
                      icon: const Icon(Icons.copy_rounded, size: 13),
                      label: Text(
                        'Copy Markdown',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textSecondary,
                        backgroundColor: bgSurface,
                        side: BorderSide(color: borderSubtle),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 10,
                        ),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Spaced 3×3 Bento Grid (01..09 Left-to-Right)
          Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 1-Column Stack (< 720px)
                if (constraints.maxWidth < 720) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int idx = 0; idx < _sections.length; idx++) ...[
                        if (idx > 0) const SizedBox(height: 10),
                        bentoSection(idx),
                      ],
                      const SizedBox(height: 10),
                      launchpadCard,
                    ],
                  );
                }

                // 2-Column Bento Grid (720px – 1039px)
                if (constraints.maxWidth < 1040) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int row = 0; row < 4; row++) ...[
                        if (row > 0) const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: bentoSection(row * 2)),
                            const SizedBox(width: 10),
                            Expanded(child: bentoSection(row * 2 + 1)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      launchpadCard,
                    ],
                  );
                }

                // 3×3 Left-to-Right Spaced Bento Grid (>= 1040px)
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Row 1: 01 Goal | 02 Game Spec | 03 Tech Spec
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: bentoSection(0)),
                        const SizedBox(width: 12),
                        Expanded(child: bentoSection(1)),
                        const SizedBox(width: 12),
                        Expanded(child: bentoSection(2)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Row 2: 04 Design Pillars | 05 Trade-Offs | 06 Core Loop
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: bentoSection(3)),
                        const SizedBox(width: 12),
                        Expanded(child: bentoSection(4)),
                        const SizedBox(width: 12),
                        Expanded(child: bentoSection(5)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Row 3: 07 Out of Scope | 08 Done When | 09 Release Launchpad
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: bentoSection(6)),
                        const SizedBox(width: 12),
                        Expanded(child: bentoSection(7)),
                        const SizedBox(width: 12),
                        Expanded(child: launchpadCard),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Card 09: Integrated v0.1 Release Launchpad Card ────────────────────────
  Widget _buildBentoLaunchpadCard(ProjectConceptBlueprint draft) {
    final isPrewarming = widget.workbench.isPrewarmingReleaseBlueprint;
    final isPrewarmed = widget.workbench.hasPrewarmedReleaseBlueprint;

    return Container(
      key: const ValueKey('bento_card_launchpad_09'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: borderBright),
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
                    Text(
                      '09',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: textMuted,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'STEP 09 · FINAL BLUEPRINT VERIFICATION',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isPrewarming || isPrewarmed)
                Container(
                  key: const ValueKey('blueprint_prewarm_status_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
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
                        ? '● v0.1 Outline Ready'
                        : '⟳ Pre-warming v0.1...',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: isPrewarmed ? accentEmerald : accentAmber,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _buildReleaseTrainPipeline(draft),
          const SizedBox(height: 10),
          _buildPrimaryApproveButton(
            key: const ValueKey('approve_concept_plan_release_btn'),
            showRebuildSecondary: true,
            expandFullWidth: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryApproveButton({
    Key? key,
    bool showRebuildSecondary = true,
    bool expandFullWidth = false,
  }) {
    final hasBuiltRelease = widget.workbench.activeReleaseBeats.isNotEmpty;
    final builtReleaseCount = widget.workbench.projectReleases
        .where((r) => r.childrenIds.isNotEmpty)
        .length;
    final canRebuildInitialV01 = showRebuildSecondary && builtReleaseCount <= 1;
    if (hasBuiltRelease) {
      return Row(
        mainAxisSize: expandFullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (canRebuildInitialV01) ...[
            Tooltip(
              message: 'Regenerate v0.1 Workbench from scratch',
              child: OutlinedButton(
                key: const ValueKey('rebuild_v01_from_concept_btn'),
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
                    horizontal: 10,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text(
                  '↻ Rebuild v0.1',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: expandFullWidth ? 1 : 0,
            child: ElevatedButton(
              key: const ValueKey('return_to_workbench_btn'),
              onPressed: widget.workbench.isAgentBusy
                  ? null
                  : () => widget.workbench.setStage(WorkbenchStage.releaseWorkbench),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentEmerald,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
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
          ),
        ],
      );
    }

    final btn = ElevatedButton(
      key: key,
      onPressed: widget.workbench.isAgentBusy
          ? null
          : () => widget.workbench.approveConceptAndBuildRelease(),
      style: ElevatedButton.styleFrom(
        backgroundColor: focalAccent,
        foregroundColor: focalAccentFg,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Text(
        widget.workbench.isAgentBusy
            ? 'Building v0.1 Workbench...'
            : 'Approve & Build v0.1 Workbench →',
        style: GoogleFonts.inter(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    if (expandFullWidth) {
      return SizedBox(width: double.infinity, child: btn);
    }
    return btn;
  }

  Widget _buildFullReviewBlock({
    required ProjectConceptBlueprint draft,
    required int sectionIdx,
    required Widget child,
  }) {
    final sec = _sections[sectionIdx];
    final isInlineOpen = _inlineEditingSectionIdx == sectionIdx;
    final isFocused = _focusedBentoSectionIdx == sectionIdx;
    final isHovered = _hoveredReviewSectionIdx == sectionIdx;
    final showHeaderActions = isHovered || isFocused || isInlineOpen;
    final options = _optionsForSection(draft, sectionIdx);
    final showCompactPills = sectionIdx != 1 && sectionIdx != 2 && options.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => _rebuild(() => _hoveredReviewSectionIdx = sectionIdx),
      onExit: (_) {
        if (_hoveredReviewSectionIdx == sectionIdx) {
          _rebuild(() => _hoveredReviewSectionIdx = null);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _rebuild(() {
            _focusedBentoSectionIdx =
                _focusedBentoSectionIdx == sectionIdx ? null : sectionIdx;
          });
        },
        child: AnimatedContainer(
          key: ValueKey('bento_section_card_$sectionIdx'),
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bgSurface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isFocused
                  ? textPrimary
                  : (isHovered ? borderBright : borderSubtle),
              width: isFocused ? 1.2 : 1.0,
            ),
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
                        Text(
                          sec.numLabel,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: isFocused ? textPrimary : textMuted,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            sec.title.toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: isFocused ? textPrimary : textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: showHeaderActions ? 1.0 : 0.0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (sectionIdx != 1 &&
                            sectionIdx != 2 &&
                            options.isEmpty) ...[
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
                                      .regenerateStage1SectionOptions(
                                        sec.optionKey,
                                      ),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: bgRecessed,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: borderSubtle),
                                ),
                                child: Text(
                                  '✦ Presets ↻',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        OutlinedButton(
                          key: ValueKey('inline_agent_toggle_$sectionIdx'),
                          onPressed: () {
                            final willOpen =
                                _inlineEditingSectionIdx != sectionIdx;
                            _rebuild(() {
                              _focusedBentoSectionIdx = sectionIdx;
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
                              horizontal: 8,
                              vertical: 3,
                            ),
                            minimumSize: const Size(0, 22),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Text(
                            isInlineOpen ? 'Close' : '💬 Focus Agent',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              child,

              // Compact 1-Line AI Preset Pills (Quiet Monochrome Footer inside Card)
              if (showCompactPills) ...[
                const SizedBox(height: 9),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      sec.isMultiSelect ? '✦ Add:' : '✦ Presets:',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
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
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? textPrimary.withValues(alpha: 0.14)
                                      : bgRecessed,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isSelected
                                        ? textPrimary.withValues(alpha: 0.65)
                                        : borderSubtle,
                                  ),
                                ),
                                child: Text(
                                  pillLabel,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isSelected
                                        ? textPrimary
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
                            : () => widget.workbench
                                .regenerateStage1SectionOptions(sec.optionKey),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: bgRecessed,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Text(
                            '↻',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // Contextual Inline Agent Drawer (when explicitly toggled via 💬 Focus Agent)
              if (isInlineOpen) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: bgRecessed,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderBright),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: TextField(
                            controller: _inlineReviewPromptController,
                            autofocus: true,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Adjust ${sec.numLabel} ${sec.shortTitle}...',
                              hintStyle: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: textMuted,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 6),
                            ),
                            onSubmitted: (_) => _submitSectionPrompt(
                              draft,
                              sectionIdx,
                              controller: _inlineReviewPromptController,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
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
                            horizontal: 10,
                            vertical: 9,
                          ),
                          minimumSize: const Size(0, 28),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        child: Text(
                          widget.workbench.isAgentBusy ? '...' : 'Apply',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
