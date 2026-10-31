part of 'project_pitch_screen.dart';

extension _PitchFullReviewExt on _ProjectPitchScreenState {
  Color get _gsT1Primary => isDark ? const Color(0xFFF9FAFB) : textPrimary;
  Color get _gsT2Body => isDark ? const Color(0xFFD1D5DB) : textSecondary;
  Color get _gsT3Label => isDark ? const Color(0xFF8E95A5) : textMuted;
  Color get _gsT4Muted => isDark ? const Color(0xFF636A78) : textMuted;
  Color get _gsCardBg => isDark ? const Color(0xFF111317) : bgSurface;
  Color get _gsCardLaunchBg => isDark ? const Color(0xFF15181E) : bgSurface;
  Color get _gsCardBorder => isDark ? const Color(0xFF22262E) : borderSubtle;
  Color get _gsCardHoverBorder =>
      isDark ? const Color(0xFF363C48) : borderBright;
  Color get _gsHairline =>
      isDark ? Colors.white.withValues(alpha: 0.065) : borderSubtle;

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
                  fontSize: 19.5,
                  fontWeight: FontWeight.w800,
                  color: _gsT1Primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${draft.coreLoopBeats.length} Epics · ${draft.gameSpec.length} Specs · Click to rename target ✎',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 14,
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
            isReadOnlySummary: false,
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
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
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
                                  style: AppTheme.displayFont(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
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
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('new_spark_reset_btn'),
                        onPressed: () => widget.workbench.resetConceptToSpark(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _gsT2Body,
                          backgroundColor: Colors.transparent,
                          side: BorderSide(color: _gsCardBorder),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          minimumSize: const Size(0, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        child: Text(
                          '+ New Project',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _copyBlueprintAsMarkdown(draft),
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: Text(
                          'Copy Markdown',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _gsT2Body,
                          backgroundColor: Colors.transparent,
                          side: BorderSide(color: _gsCardBorder),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          minimumSize: const Size(0, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (expansionCards.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  key: const ValueKey('blueprint_twist_pills_bar'),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '✦ OPTIONAL TWISTS:',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _gsT3Label,
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
                                          if (card.isSelected) {
                                            if (!d.coreLoopBeats.any(
                                              (b) => b
                                                  .toLowerCase()
                                                  .startsWith(
                                                    card.title.toLowerCase(),
                                                  ),
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
                                                        card.title
                                                            .toLowerCase(),
                                                      ),
                                                )
                                                .toList();
                                          }
                                        });
                                      },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? _gsT1Primary.withValues(alpha: 0.12)
                                        : _gsCardBg,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected
                                          ? _gsT1Primary.withValues(alpha: 0.65)
                                          : _gsCardBorder,
                                    ),
                                  ),
                                  child: Text(
                                    isSelected
                                        ? '✓ ${card.title}'
                                        : '+ ${card.title}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? _gsT1Primary
                                          : _gsT2Body,
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

        // Single-Column Vertical Stack of the 9 Section Cards (01 -> 09)
        for (int idx = 0; idx < _sections.length; idx++) ...[
          if (idx > 0) const SizedBox(height: 20),
          sectionCard(idx),
        ],
        const SizedBox(height: 20),
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
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
      decoration: BoxDecoration(
        color: _gsCardLaunchBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentEmerald.withValues(alpha: 0.45),
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
                          fontWeight: FontWeight.w700,
                          color: _gsT4Muted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'STEP 09 · FINAL BLUEPRINT VERIFICATION',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: _gsT3Label,
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
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _gsCardBg,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: _gsCardBorder),
                    ),
                    child: Text(
                      isPrewarmed
                          ? '● v0.1 Outline Ready'
                          : '⟳ Pre-warming v0.1...',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _gsT2Body,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 620) {
                return Column(
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
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _buildReleaseTrainPipeline(draft)),
                  const SizedBox(width: 24),
                  _buildPrimaryApproveButton(
                    key: const ValueKey('approve_concept_plan_release_btn'),
                    showRebuildSecondary: true,
                    expandFullWidth: false,
                  ),
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
                  foregroundColor: _gsT2Body,
                  backgroundColor: Colors.transparent,
                  side: BorderSide(color: _gsCardBorder),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  '↻ Rebuild v0.1',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
                foregroundColor: const Color(0xFF051B11),
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
                '✓ Return to Workbench →',
                style: GoogleFonts.inter(
                  fontSize: 15,
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
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: const Color(0xFF051B11),
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
            ? 'Building v0.1 Workbench...'
            : 'Approve & Build v0.1 Workbench →',
        style: GoogleFonts.inter(
          fontSize: 15.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    if (expandFullWidth) {
      return SizedBox(width: double.infinity, child: btn);
    }
    return btn;
  }

  Widget? _buildHeaderAddActionForSection(int sectionIdx) {
    switch (sectionIdx) {
      case 3: // 04 Design Pillars
        return OutlinedButton(
          key: const ValueKey('section_3_add_pillar_btn'),
          onPressed: () => _startInlineEdit('add_pillar', ''),
          style: _headerNeutralButtonStyle(),
          child: Text(
            '+ Add Pillar',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case 4: // 05 Trade-Offs
        return OutlinedButton(
          key: const ValueKey('section_4_add_guardrail_btn'),
          onPressed: () => _startInlineEdit('add_tradeoff', ''),
          style: _headerNeutralButtonStyle(),
          child: Text(
            '+ Add Trade-Off',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case 5: // 06 Core Loop
        return OutlinedButton(
          key: const ValueKey('section_5_add_beat_btn'),
          onPressed: () => _startInlineEdit('add_beat', ''),
          style: _headerNeutralButtonStyle(),
          child: Text(
            '+ Add Beat',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case 6: // 07 Out of Scope
        return OutlinedButton(
          key: const ValueKey('section_6_add_cut_btn'),
          onPressed: () => _startInlineEdit('add_exclusion', ''),
          style: _headerNeutralButtonStyle(),
          child: Text(
            '+ Add Cut',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      default:
        return null;
    }
  }

  ButtonStyle _headerNeutralButtonStyle({bool isActive = false}) {
    return OutlinedButton.styleFrom(
      foregroundColor: isActive ? _gsCardBg : _gsT2Body,
      backgroundColor: isActive ? _gsT1Primary : Colors.transparent,
      side: BorderSide(color: _gsCardBorder),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      minimumSize: const Size(0, 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
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
    final isFocused = _focusedBentoSectionIdx == sectionIdx;
    final isHovered = _hoveredReviewSectionIdx == sectionIdx;
    final options = _optionsForSection(draft, sectionIdx);
    final showCompactPills =
        sectionIdx != 1 && sectionIdx != 2 && options.isNotEmpty;
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
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
          decoration: BoxDecoration(
            color: _gsCardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isFocused
                  ? _gsT1Primary.withValues(alpha: 0.75)
                  : (isHovered ? _gsCardHoverBorder : _gsCardBorder),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Open Card Header + Hairline (No Inner Pill Box)
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
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            sec.numLabel,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isFocused ? _gsT1Primary : _gsT4Muted,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              sec.title.toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: isFocused ? _gsT1Primary : _gsT3Label,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              sec.purpose,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _gsT4Muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (headerAddBtn != null) ...[
                          headerAddBtn,
                          const SizedBox(width: 8),
                        ],
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
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: _gsCardBorder),
                                ),
                                child: Text(
                                  '✦ Presets ↻',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _gsT3Label,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
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
                          style: _headerNeutralButtonStyle(
                            isActive: isInlineOpen,
                          ),
                          child: Text(
                            isInlineOpen ? 'Close' : 'Ask AI',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Quiet Greyscale Preset Strip (Placed right below header so clicking presets never shifts pill Y position)
              if (showCompactPills) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      sec.isMultiSelect ? '✦ Add:' : '✦ Presets:',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _gsT4Muted,
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
                              borderRadius: BorderRadius.circular(5),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Text(
                                  pillLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    decoration: isSelected
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                    color:
                                        isSelected ? _gsT1Primary : _gsT3Label,
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
                        key: ValueKey(
                          'compact_shuffle_options_btn_$sectionIdx',
                        ),
                        onTap: widget.workbench.isAgentBusy
                            ? null
                            : () => widget.workbench
                                .regenerateStage1SectionOptions(sec.optionKey),
                        borderRadius: BorderRadius.circular(5),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          child: Text(
                            '↻',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _gsT3Label,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 14),
              child,

              // Contextual Inline Agent Input (when toggled via Ask AI)
              if (isInlineOpen) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: _gsHairline)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inlineReviewPromptController,
                          autofocus: true,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: _gsT1Primary,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Ask AI to refine ${sec.numLabel} ${sec.shortTitle}...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 13.5,
                              color: _gsT4Muted,
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
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: widget.workbench.isAgentBusy
                            ? null
                            : () => _submitSectionPrompt(
                                  draft,
                                  sectionIdx,
                                  controller: _inlineReviewPromptController,
                                ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          minimumSize: const Size(0, 34),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(
                          widget.workbench.isAgentBusy ? '...' : 'Update',
                          style: GoogleFonts.inter(
                            fontSize: 13,
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
