part of 'project_pitch_screen.dart';

extension _PitchFullReviewExt on _ProjectPitchScreenState {
  Color get _gsT1Primary => textPrimary;
  Color get _gsT3Label => textSecondary;
  Color get _gsT4Muted => textMuted;
  Color get _gsCardBg => bgSurface;
  Color get _gsCardLaunchBg => bgSurface;
  Color get _gsCardBorder => borderSubtle;
  Color get _gsCardHoverBorder => borderBright;
  Color get _gsHairline => borderSubtle;

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

  // Open Release Target Summary inside Card 09 (Zero Nested Box)
  Widget _buildReleaseStepCard(
    String fullTitle, {
    required ProjectConceptBlueprint draft,
    required bool isFirst,
    required int index,
    VoidCallback? onTap,
  }) {
    final builtEpicCount = widget.workbench.activeReleaseBeats.length;
    final subtitleText = builtEpicCount > 0
        ? '$builtEpicCount Epics · ${draft.coreLoopBeats.length} Loop Beats · ${draft.gameSpec.length} Specs · Click to rename target ✎'
        : '${draft.coreLoopBeats.length} Loop Beats · ${draft.gameSpec.length} Specs · Click to rename target ✎';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('stage1_release_train_card_$index'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fullTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: _measureLeadFontSize,
                  fontWeight: FontWeight.w700,
                  color: _gsT1Primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: _measureBodyFontSize - 1.5,
                  fontWeight: FontWeight.w500,
                  color: _gsT3Label,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Spacious Single-Column Concept Blueprint (01 -> 09 Top-to-Bottom) ─────
  // Only the 9 section cards are boxes; the Project Header sits openly on the canvas.
  Widget _buildFullReviewWorkspace(ProjectConceptBlueprint draft) {
    final intake = widget.workbench.sparkIntake;
    final expansionCards = intake?.expansionCards ?? const [];

    Widget sectionCard(int idx) => _buildFullReviewBlock(
          draft: draft,
          sectionIdx: idx,
          child: _buildSectionContentWidget(
            draft,
            idx,
          ),
        );

    final launchpadCard = _buildBentoLaunchpadCard(draft);

    return Column(
      key: const ValueKey('project_blueprint_card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Open Project Header on the Canvas (No Outer Wrapper Box)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                runSpacing: 12,
                spacing: 16,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PROJECT CONCEPT BLUEPRINT',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: _gsT3Label,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_activeInlineEditKey == 'blueprint_project_title')
                        SizedBox(
                          width: 420,
                          child: _buildInlineEditorBox(
                            editKey: 'blueprint_project_title',
                            hintText: 'Project title...',
                            onSave: _saveInlineProjectTitle,
                          ),
                        )
                      else
                        InkWell(
                          key: const ValueKey(
                            'stage1_blueprint_title_inline_trigger',
                          ),
                          onTap: () => _promptEditProjectTitle(
                            draft,
                            key: 'blueprint_project_title',
                          ),
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  draft.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: _measureTitleFontSize,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.35,
                                    color: _gsT1Primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '✎',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 15,
                                  color: _gsT4Muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  InkWell(
                    key: const ValueKey('new_spark_reset_btn'),
                    onTap: () => widget.workbench.resetConceptToSpark(),
                    borderRadius: BorderRadius.circular(5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        '+ New Project',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _gsT3Label,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (expansionCards.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  key: const ValueKey('blueprint_twist_pills_bar'),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '✦ OPTIONAL TWISTS:',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _gsT4Muted,
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
                                        widget.workbench
                                            .toggleSparkExpansionCard(i);
                                        widget.workbench
                                            .updateConceptDraft((d) {
                                          final beatEntry =
                                              '${card.title}: ${card.description}';
                                          final lowerTitle =
                                              card.title.toLowerCase();
                                          if (card.isSelected) {
                                            if (!d.coreLoopBeats.any(
                                              (b) => b
                                                  .toLowerCase()
                                                  .startsWith(lowerTitle),
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
                                                      .startsWith(lowerTitle),
                                                )
                                                .toList();
                                          }
                                        });
                                      },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    isSelected
                                        ? '✓ ${card.title}'
                                        : '+ ${card.title}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? _gsT1Primary
                                          : _gsT3Label,
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
            ],
          ),
        ),

        // Single-Column 680px Quiet Document Stack (01 -> 08 -> 09 Release Target):
        for (int idx = 0; idx < _sections.length; idx++) ...[
          if (idx > 0) SizedBox(height: _measureCardGap),
          sectionCard(idx),
        ],
        SizedBox(height: _measureCardGap),
        launchpadCard,
      ],
    );
  }

  // ── Card 09: Final Blueprint Verification (Selective Color on Primary CTA) ─
  Widget _buildBentoLaunchpadCard(ProjectConceptBlueprint draft) {
    final isPrewarming = widget.workbench.isPrewarmingReleaseBlueprint;
    final isPrewarmed = widget.workbench.hasPrewarmedReleaseBlueprint;

    return Container(
      key: const ValueKey('bento_card_launchpad_09'),
      padding: EdgeInsets.symmetric(
        horizontal: _measureCardPadH,
        vertical: _measureCardPadV,
      ),
      decoration: BoxDecoration(
        color: _gsCardLaunchBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _gsCardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _gsHairline)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        '09',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _gsT4Muted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'RELEASE TARGET',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: _gsT3Label,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isPrewarming || isPrewarmed)
                  Text(
                    isPrewarmed ? '● v0.1 Ready' : '⟳ Drafting v0.1...',
                    key: const ValueKey('blueprint_prewarm_status_badge'),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isPrewarmed ? _gsT3Label : _gsT4Muted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildReleaseTrainPipeline(draft),
              const SizedBox(height: 16),
              _buildPrimaryApproveButton(
                key: const ValueKey('approve_concept_plan_release_btn'),
                showRebuildSecondary: true,
                expandFullWidth: true,
              ),
            ],
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
              child: InkWell(
                key: const ValueKey('rebuild_v01_from_concept_btn'),
                onTap: widget.workbench.isAgentBusy
                    ? null
                    : () => widget.workbench.approveConceptAndBuildRelease(
                          releaseId:
                              widget.workbench.projectReleases.firstOrNull?.id,
                        ),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Text(
                    '↻ Rebuild v0.1',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _gsT3Label,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            flex: expandFullWidth ? 1 : 0,
            child: ElevatedButton(
              key: const ValueKey('return_to_workbench_btn'),
              onPressed: widget.workbench.isAgentBusy
                  ? null
                  : () => widget.workbench.setStage(WorkbenchStage.releaseWorkbench),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: const Color(0xFF06281E),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: Text(
                'Workbench',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
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
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: const Color(0xFF06281E),
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
      child: Text(
        widget.workbench.isAgentBusy
            ? 'Building v0.1...'
            : 'Approve & Build v0.1 →',
        style: GoogleFonts.inter(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (expandFullWidth) {
      return SizedBox(width: double.infinity, child: btn);
    }
    return btn;
  }

  Widget? _buildHeaderAddActionForSection(int sectionIdx) {
    Widget buildBtn(String keyName, String editKey, String label) => InkWell(
          key: ValueKey(keyName),
          onTap: () => _startInlineEdit(editKey, ''),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _gsT3Label,
              ),
            ),
          ),
        );

    return switch (sectionIdx) {
      3 => buildBtn('section_3_add_pillar_btn', 'add_pillar', '+ Add'),
      4 => buildBtn(
          'section_4_add_guardrail_btn',
          'add_tradeoff',
          '+ Add',
        ),
      5 => buildBtn('section_5_add_beat_btn', 'add_beat', '+ Add'),
      6 => buildBtn('section_6_add_cut_btn', 'add_exclusion', '+ Add'),
      _ => null,
    };
  }

  Widget _buildFullReviewBlock({
    required ProjectConceptBlueprint draft,
    required int sectionIdx,
    required Widget child,
  }) {
    final sec = _sections[sectionIdx];
    final isFocused = _focusedBentoSectionIdx == sectionIdx;
    final isHovered = _hoveredReviewSectionIdx == sectionIdx;
    final isDrawerOpen = _openRefineDrawerSectionIdx == sectionIdx;
    final isDraftingThisSection =
        widget.workbench.isSynthesizingConceptSection(sectionIdx);
    final isQueuedSection =
        widget.workbench.isConceptSectionQueued(sectionIdx);
    final headerAddBtn = _buildHeaderAddActionForSection(sectionIdx);

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
          padding: EdgeInsets.symmetric(
            horizontal: _measureCardPadH,
            vertical: _measureCardPadV,
          ),
          decoration: BoxDecoration(
            color: _gsCardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (isFocused || isDrawerOpen || isDraftingThisSection)
                  ? _gsT1Primary.withValues(alpha: 0.75)
                  : (isHovered ? _gsCardHoverBorder : _gsCardBorder),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Clean Card Header + Hairline (No Truncated sec.purpose Subtitle)
              Container(
                padding: const EdgeInsets.only(bottom: 11),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: _gsHairline)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            sec.numLabel,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isFocused ? _gsT1Primary : _gsT4Muted,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              sec.title.toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                                color: isFocused ? _gsT1Primary : _gsT3Label,
                              ),
                            ),
                          ),
                          if (isDraftingThisSection || isQueuedSection) ...[
                            const SizedBox(width: 10),
                            Text(
                              isDraftingThisSection
                                  ? '⟳ Drafting...'
                                  : 'Queued',
                              key: ValueKey(
                                'concept_section_build_status_$sectionIdx',
                              ),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDraftingThisSection
                                    ? _gsT1Primary
                                    : _gsT4Muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (headerAddBtn != null) ...[
                          headerAddBtn,
                          const SizedBox(width: 10),
                        ],
                        InkWell(
                          key: ValueKey('refine_drawer_toggle_btn_$sectionIdx'),
                          onTap: () {
                            _rebuild(() {
                              if (_openRefineDrawerSectionIdx == sectionIdx) {
                                _openRefineDrawerSectionIdx = null;
                              } else {
                                _openRefineDrawerSectionIdx = sectionIdx;
                                _focusedBentoSectionIdx = sectionIdx;
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              isDrawerOpen ? 'Refine ▴' : 'Refine ▾',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: isDrawerOpen ? _gsT1Primary : _gsT3Label,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),
              child,

              if (isDrawerOpen)
                _buildRefineSectionDrawer(
                  draft: draft,
                  sectionIdx: sectionIdx,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRefineSectionDrawer({
    required ProjectConceptBlueprint draft,
    required int sectionIdx,
  }) {
    final sec = _sections[sectionIdx];
    final options = _optionsForSection(draft, sectionIdx);
    final hasActiveSingleSelect =
        !sec.isMultiSelect && _selectedOptionBySection[sectionIdx] != null;

    Future<void> triggerRefreshOptions() async {
      if (widget.workbench.isAgentBusy) return;
      await widget.workbench.regenerateStage1SectionOptions(sec.optionKey);
      if (!mounted) return;
      _rebuild(() {
        _initialSectionDefaults.remove(sectionIdx);
        _selectedOptionBySection.remove(sectionIdx);
        _selectedOptionsBySection.remove(sectionIdx);
      });
    }

    return Container(
      key: ValueKey('refine_drawer_container_$sectionIdx'),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gsCardBorder),
      ),
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
                    Flexible(
                      child: Text(
                        sec.isMultiSelect
                            ? 'PICK TO ADD TO ${sec.title.toUpperCase()}'
                            : 'PICK AN ALTERNATIVE ${sec.title.toUpperCase()}',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: _gsT3Label,
                        ),
                      ),
                    ),
                    if (hasActiveSingleSelect) ...[
                      const SizedBox(width: 10),
                      InkWell(
                        key: ValueKey(
                          'restore_original_section_btn_$sectionIdx',
                        ),
                        onTap: () {
                          _restoreSectionDefault(draft, sectionIdx);
                          _rebuild(() {
                            _selectedOptionBySection.remove(sectionIdx);
                          });
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            '↺ Restore',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _gsT1Primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: ValueKey('compact_shuffle_options_btn_$sectionIdx'),
                onTap: widget.workbench.isAgentBusy
                    ? null
                    : triggerRefreshOptions,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Text(
                    '↻ Refresh',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _gsT3Label,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (options.isNotEmpty) ...[
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                Widget buildOptionCard(int optIdx) {
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
                  final statusLabel = sec.isMultiSelect
                      ? (isSelected ? '✓ Added' : '+ Add')
                      : (isSelected ? '● Active' : 'Swap →');

                  // Section 05 (Trade-Offs): format option card in telegraphic style (over losePart)
                  Widget descriptionWidget;
                  if (sectionIdx == 4 &&
                      rawOpt.toLowerCase().contains(' over ')) {
                    final telegraphic = _formatTelegraphicTradeOff(rawOpt);
                    descriptionWidget = Text(
                      'over ${telegraphic.lose}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.4,
                        color: _gsT3Label,
                      ),
                    );
                  } else {
                    descriptionWidget = Text(
                      split.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.45,
                        color: _gsT3Label,
                      ),
                    );
                  }

                  return Material(
                    color: Colors.transparent,
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
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _gsCardBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? _gsT1Primary : _gsCardBorder,
                            width: isSelected ? 1.4 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    sectionIdx == 4 &&
                                            rawOpt
                                                .toLowerCase()
                                                .contains(' over ')
                                        ? _formatTelegraphicTradeOff(rawOpt).win
                                        : split.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: _gsT1Primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  statusLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? _gsT1Primary
                                        : _gsT4Muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            descriptionWidget,
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // 3-across option cards for Double-Width Section 01 (Goal) on desktop (>= 900px)
                final isDoubleWidthCard = sectionIdx == 0;
                if (isDoubleWidthCard &&
                    _viewportWidth >= 900 &&
                    options.length <= 3) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < options.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(child: buildOptionCard(i)),
                        ],
                      ],
                    ),
                  );
                }

                // Vertical stack inside Half-Width (50%) cards (02..08) or narrow screens
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < options.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      buildOptionCard(i),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
