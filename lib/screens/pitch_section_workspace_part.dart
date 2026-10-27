part of 'project_pitch_screen.dart';

extension _PitchSectionWorkspaceExt on _ProjectPitchScreenState {
  // ── Direct Text Edit Dialog for Any Section Callout or Row ──────────────────
  void _showDirectSectionTextEditDialog({
    required String title,
    required String initialText,
    required ValueChanged<String> onSave,
  }) {
    final controller = TextEditingController(text: initialText);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: borderBright),
          ),
          title: Text(
            'Edit $title',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          content: SizedBox(
            width: 480,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              style: GoogleFonts.inter(fontSize: 13.5, color: textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: bgRecessed,
                hintText: 'Enter $title...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: borderSubtle),
                ),
              ),
              onSubmitted: (val) {
                final trimmed = val.trim();
                if (trimmed.isNotEmpty) onSave(trimmed);
                Navigator.of(ctx).pop();
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: focalAccent,
                foregroundColor: focalAccentFg,
                elevation: 0,
              ),
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) onSave(trimmed);
                Navigator.of(ctx).pop();
              },
              child: Text(
                'Save',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Steps `01`–`08`: De-Boxed Full-Width Single-Section Workspace ──────────
  Widget _buildFocusedSectionWorkspace(ProjectConceptBlueprint draft, int sectionIdx) {
    final sec = _sections[sectionIdx];
    final agentNote = _agentNotesBySection[sectionIdx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // SECTION 1: DE-BOXED EDITORIAL ARTIFACT SECTION WORKSPACE
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: borderSubtle),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 8,
                    spacing: 12,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SECTION ${sec.numLabel} / 08',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: accentCyan,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '· ${sec.shortTitle.toUpperCase()}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 11,
                            color: textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Click any item below to edit directly',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        sec.numLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: accentCyan,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          sec.title,
                          style: AppTheme.displayFont(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sec.purpose,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Full-Width Editorial Artifact Content (No Outer 4-Sided Box)
            _buildSectionContentWidget(draft, sectionIdx),
          ],
        ),

        const SizedBox(height: 16),

        // SECTION 2: BOXLESS AGENT OPTIONS (Top Hairline Divider + Listed Option Rows)
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: borderSubtle),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: borderSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentCyan,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'AGENT · ${widget.workbench.conversationModel.toUpperCase()}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: accentCyan,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        sec.question,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    if (sec.isMultiSelect) ...[
                      const SizedBox(width: 8),
                      Container(
                        key: ValueKey('multi_select_badge_$sectionIdx'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        child: Text(
                          '+ / ✓ MULTI-SELECT · ADD ANY',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: accentEmerald,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    InkWell(
                      key: const ValueKey('regenerate_section_options_btn'),
                      onTap: () {
                        _rebuild(() {
                          _selectedOptionBySection.remove(sectionIdx);
                          _selectedOptionsBySection.remove(sectionIdx);
                        });
                        widget.workbench.regenerateStage1SectionOptions(
                          sec.optionKey,
                        );
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Text(
                          '↻ Refresh Options',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Vertical Listed Option Rows (Full-Width, Hairline-Divided)
              Builder(
                builder: (context) {
                  final options = _optionsForSection(draft, sectionIdx);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int optIdx = 0; optIdx < options.length; optIdx++)
                        _buildAgentOptionCard(
                          draft: draft,
                          sectionIdx: sectionIdx,
                          optIdx: optIdx,
                          label: options[optIdx],
                          isSelected: _isSectionOptionSelected(sectionIdx, optIdx),
                        ),
                    ],
                  );
                },
              ),

              if (agentNote != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: accentEmerald, width: 2),
                    ),
                  ),
                  child: Text(
                    agentNote,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Sticky Bottom Studio Dock (Steps `01`–`09` + Step `10 Full Review`) ─────
  Widget _buildConceptStickyBottomDock(ProjectConceptBlueprint draft) {
    final isFullReview = _currentStep >= _sections.length;
    if (isFullReview) {
      return Container(
        key: const ValueKey('concept_sticky_bottom_dock'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: bgSurface,
          border: Border(top: BorderSide(color: borderBright)),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 10,
              spacing: 16,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () => _goToStep(_sections.length - 1),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textPrimary,
                        backgroundColor: bgRecessed,
                        side: BorderSide(color: borderSubtle),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      child: Text(
                        '← Back to Section 08',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentEmerald.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: accentEmerald.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        'ALL 8 SECTIONS READY',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accentEmerald,
                        ),
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
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildPrimaryApproveButton(
                      key: const ValueKey('approve_concept_plan_release_btn'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final sectionIdx = _currentStep;
    final sec = _sections[sectionIdx];
    final nextTitle = sectionIdx + 1 < _sections.length
        ? 'Next: ${_sections[sectionIdx + 1].shortTitle} →'
        : 'Next: Full Blueprint Review →';

    return Container(
      key: const ValueKey('concept_sticky_bottom_dock'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: bgSurface,
        border: Border(top: BorderSide(color: borderBright)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // [ASK AGENT] Input Bar
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: bgRecessed,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: borderSubtle),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '[ASK AGENT]',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: textSecondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Focus(
                              onKeyEvent: (node, event) =>
                                  _handleMultilinePitchKeyEvent(
                                event,
                                _agentPromptController,
                                onSubmit: () =>
                                    _submitSectionPrompt(draft, sectionIdx),
                              ),
                              child: TextField(
                                key: const ValueKey('concept_chat_input_field'),
                                controller: _agentPromptController,
                                focusNode: _conceptChatFocusNode,
                                minLines: 1,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                inputFormatters: const [
                                  MaxColumnLineWrapFormatter(
                                    maxCharsPerLine: 70,
                                  ),
                                ],
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: textPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintMaxLines: 1,
                                  hintText:
                                      'Tell the Agent how to change or expand ${sec.title} (70 chars/line · Shift+Enter for new line)...',
                                  hintStyle: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: textMuted,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onSubmitted: (_) =>
                                    _submitSectionPrompt(draft, sectionIdx),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: widget.workbench.isAgentBusy
                        ? null
                        : () => _submitSectionPrompt(draft, sectionIdx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      backgroundColor: bgRecessed,
                      side: BorderSide(color: borderBright),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    child: Text(
                      widget.workbench.isAgentBusy ? 'Updating...' : 'Send to Agent',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Step Navigation Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton(
                    onPressed: sectionIdx == 0
                        ? null
                        : () => _goToStep(sectionIdx - 1),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      backgroundColor: bgRecessed,
                      side: BorderSide(color: borderSubtle),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    child: Text(
                      '← Previous Section',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        key: const ValueKey('skip_to_full_review_btn'),
                        onPressed: () => _goToStep(_sections.length),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          backgroundColor: bgRecessed,
                          side: BorderSide(
                            color: accentAmber.withValues(alpha: 0.55),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        child: Text(
                          'Review Full Blueprint ◫',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        key: const ValueKey('next_section_btn'),
                        onPressed: () => _goToStep(sectionIdx + 1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: focalAccent,
                          foregroundColor: focalAccentFg,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        child: Text(
                          nextTitle,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgentOptionCard({
    required ProjectConceptBlueprint draft,
    required int sectionIdx,
    required int optIdx,
    required String label,
    required bool isSelected,
  }) {
    final parsed = _splitOptionIntoCardTitleAndBody(label, sectionIdx, optIdx);
    final sec = _sections[sectionIdx];
    final isMulti = sec.isMultiSelect;
    final activeBarColor = isMulti ? accentEmerald : accentCyan;

    return Material(
      color: isSelected ? bgHover.withValues(alpha: 0.45) : Colors.transparent,
      child: InkWell(
        key: ValueKey('agent_option_card_${sectionIdx}_$optIdx'),
        onTap: () => _selectSectionOption(draft, sectionIdx, optIdx),
        child: Container(
          padding: EdgeInsets.fromLTRB(isSelected ? 13 : 8, 10, 8, 10),
          decoration: BoxDecoration(
            border: Border(
              left: isSelected
                  ? BorderSide(color: activeBarColor, width: 3)
                  : BorderSide.none,
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Unified Selection Indicator: Radio Circle for single-select, Check/Add for multi-select
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: isMulti
                    ? Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.add_circle_outline_rounded,
                        size: 16,
                        color: isSelected ? accentEmerald : textMuted,
                      )
                    : Container(
                        width: 15,
                        height: 15,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? accentCyan : Colors.transparent,
                          border: Border.all(
                            color: isSelected ? accentCyan : textMuted,
                            width: 1.4,
                          ),
                        ),
                        child: isSelected
                            ? Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: bgBase,
                                ),
                              )
                            : null,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(
                          parsed.title,
                          style: AppTheme.displayFont(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              optIdx == 0 ? 'RECOMMENDED' : 'OPTION 0${optIdx + 1}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: optIdx == 0 ? accentCyan : textSecondary,
                              ),
                            ),
                            if (isMulti) ...[
                              const SizedBox(width: 10),
                              Text(
                                isSelected
                                    ? '✓ Added to ${sec.shortTitle}'
                                    : '+ Add to ${sec.shortTitle}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? accentEmerald
                                      : textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      parsed.description,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.42,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 6 Distinct Structural Section Layouts ──────────────────────────────────
  Widget _buildSectionContentWidget(
    ProjectConceptBlueprint draft,
    int sectionIdx, {
    bool isReadOnlySummary = false,
  }) {
    switch (sectionIdx) {
      case 0: // 01 Goal — Option A: Strategy Badge + Bold 1-Sentence Headline + 3 Scannable Clause Cards
        return _buildStructuredGoalSection(
          draft,
          onEditTap: isReadOnlySummary
              ? null
              : () => _showDirectSectionTextEditDialog(
                    title: '01 Goal',
                    initialText: ProjectConceptBlueprint.sanitizeGoalText(draft.goal),
                    onSave: (val) => widget.workbench.updateConceptDraft(
                      (d) => d.goal = ProjectConceptBlueprint.sanitizeGoalText(val),
                    ),
                  ),
        );
      case 1: // 02 Game Spec — 2×2 Key-Value Spec Grid (Direct Click-to-Edit)
        return _buildKvSpecGrid(
          isGameSpec: true,
          keys: const ['CAMERA VIEW', 'CONTROLS', 'PLAYER MODE', 'ARENA STRUCTURE'],
          values: draft.gameSpec,
        );
      case 2: // 03 Tech Spec — 2×2 Key-Value Spec Grid (Direct Click-to-Edit)
        return _buildKvSpecGrid(
          isGameSpec: false,
          keys: const ['ENGINE', 'PLATFORM', 'ASSET PIPELINE', 'NETWORK / SAVE'],
          values: draft.techSpec,
        );
      case 3: // 04 Design Pillars — 3 Side-by-Side Pillar Playing Cards + Inline Add/Remove
        return _buildDesignPillarCards(draft, isReadOnlySummary: isReadOnlySummary);
      case 4: // 05 Trade-Offs — Split X OVER Y Comparison Bars + Inline Add/Remove
        return _buildTradeOffSplitBars(
          draft.tradeOffs,
          onEditItem: (i, val) => widget.workbench.updateConceptDraft((d) {
            final next = List<String>.from(d.tradeOffs);
            next[i] = val;
            d.tradeOffs = next;
          }),
          onDeleteItem: (!isReadOnlySummary && draft.tradeOffs.length > 1)
              ? (i) => widget.workbench.updateConceptDraft((d) {
                    final next = List<String>.from(d.tradeOffs)..removeAt(i);
                    d.tradeOffs = next;
                  })
              : null,
          onAddItem: isReadOnlySummary
              ? null
              : () => _showDirectSectionTextEditDialog(
                    title: 'Add Trade-Off (X over Y)',
                    initialText: 'Immediate arcade responsiveness over complex simulation depth',
                    onSave: (val) => widget.workbench.updateConceptDraft((d) {
                      d.tradeOffs = [...d.tradeOffs, val];
                    }),
                  ),
        );
      case 5: // 06 Core Loop — Connected Beat Cycle Rows + Inline Add/Remove/Reorder
        return _buildIndexedRows(
          prefix: 'BEAT',
          items: draft.coreLoopBeats,
          isCoreLoop: true,
          onEditItem: (i, val) => widget.workbench.updateConceptDraft((d) {
            final next = List<String>.from(d.coreLoopBeats);
            next[i] = val;
            d.coreLoopBeats = next;
          }),
          onReorderItem: (!isReadOnlySummary && draft.coreLoopBeats.length > 1)
              ? (oldIdx, newIdx) => widget.workbench.updateConceptDraft((d) {
                    if (newIdx < 0 || newIdx >= d.coreLoopBeats.length) return;
                    final next = List<String>.from(d.coreLoopBeats);
                    final moved = next.removeAt(oldIdx);
                    next.insert(newIdx, moved);
                    d.coreLoopBeats = next;
                  })
              : null,
          onDeleteItem: (!isReadOnlySummary && draft.coreLoopBeats.length > 1)
              ? (i) => widget.workbench.updateConceptDraft((d) {
                    final next = List<String>.from(d.coreLoopBeats)..removeAt(i);
                    d.coreLoopBeats = next;
                  })
              : null,
          onAddItem: isReadOnlySummary
              ? null
              : () => _showDirectSectionTextEditDialog(
                    title: 'Add Core Loop Beat',
                    initialText: 'Extract & Upgrade: Spend gathered resources on one immediate loadout upgrade.',
                    onSave: (val) => widget.workbench.updateConceptDraft((d) {
                      d.coreLoopBeats = [...d.coreLoopBeats, val];
                    }),
                  ),
        );
      case 6: // 07 Out of Scope — 2-Column Recessed Guardrail Grid + Inline Add/Remove
        return _buildCutGuardrailChips(
          draft.exclusions,
          onEditItem: (i, val) => widget.workbench.updateConceptDraft((d) {
            final next = List<String>.from(d.exclusions);
            next[i] = val;
            d.exclusions = next;
          }),
          onDeleteItem: (!isReadOnlySummary && draft.exclusions.length > 1)
              ? (i) => widget.workbench.updateConceptDraft((d) {
                    final next = List<String>.from(d.exclusions)..removeAt(i);
                    d.exclusions = next;
                  })
              : null,
          onAddItem: isReadOnlySummary
              ? null
              : () => _showDirectSectionTextEditDialog(
                    title: 'Add Out of Scope Exclusion (Cut)',
                    initialText: 'No procedural world generation or multiplayer networking in v0.1',
                    onSave: (val) => widget.workbench.updateConceptDraft((d) {
                      d.exclusions = [...d.exclusions, val];
                    }),
                  ),
        );
      case 7: // 08 Done When — Acceptance Callout Statement with Highlighted Playtest Metrics
      default:
        return _buildCalloutStatement(
          draft.doneWhen,
          highlightMetrics: true,
          onEditTap: () => _showDirectSectionTextEditDialog(
            title: '08 Done When',
            initialText: draft.doneWhen,
            onSave: (val) => widget.workbench.updateConceptDraft((d) => d.doneWhen = val),
          ),
        );
    }
  }

  Widget _buildStructuredGoalSection(
    ProjectConceptBlueprint draft, {
    VoidCallback? onEditTap,
  }) {
    final sanitized = ProjectConceptBlueprint.sanitizeGoalText(draft.goal);
    final colonIdx = sanitized.indexOf(':');
    String strategyBadge = 'PROTOTYPE TARGET';
    String headline = sanitized;

    if (colonIdx > 0 && colonIdx <= 48 && colonIdx < sanitized.length - 1) {
      strategyBadge = sanitized.substring(0, colonIdx).trim().toUpperCase();
      headline = sanitized.substring(colonIdx + 1).trim();
    } else {
      final selectedOptIdx = _selectedOptionBySection[0];
      final goalOpts = draft.sectionOptions['goal'] ?? const <String>[];
      if (selectedOptIdx != null &&
          selectedOptIdx >= 0 &&
          selectedOptIdx < goalOpts.length) {
        final opt = goalOpts[selectedOptIdx];
        final optColon = opt.indexOf(':');
        if (optColon > 0 && optColon <= 48) {
          strategyBadge = opt.substring(0, optColon).trim().toUpperCase();
        }
      }
    }

    final clauses = _extractGoalClauses(headline, draft.coreLoopBeats);
    final clauseAccents = <Color>[accentCyan, accentAmber, accentEmerald];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('stage1_goal_structured_card'),
        onTap: onEditTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8, right: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: accentCyan,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Strategy Badge Row + Click to Edit hint
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentCyan.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: accentCyan.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: accentCyan,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          strategyBadge,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: accentCyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (onEditTap != null)
                    Text(
                      '✎ Click to edit',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: textMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // 2. Bold 1-Sentence Headline
              Text(
                headline,
                style: GoogleFonts.inter(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                  letterSpacing: -0.2,
                  color: textPrimary,
                ),
              ),
              if (clauses.isNotEmpty) ...[
                const SizedBox(height: 14),
                // 3. 3 Scannable Clause Cards (01, 02, 03)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final useRow = constraints.maxWidth >= 520;
                    final cards = List<Widget>.generate(clauses.length, (i) {
                      final clause = clauses[i];
                      final accent = clauseAccents[i % clauseAccents.length];
                      final numTag = (i + 1).toString().padLeft(2, '0');
                      return Container(
                        key: ValueKey('stage1_goal_clause_card_$i'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: bgRecessed,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$numTag · ${clause.title.toUpperCase()}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: accent,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              clause.body,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                height: 1.42,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    });

                    if (useRow) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < cards.length; i++) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(child: cards[i]),
                            ],
                          ],
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < cards.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          cards[i],
                        ],
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<({String title, String body})> _extractGoalClauses(
    String headline,
    List<String> coreLoopBeats,
  ) {
    // 1. Check if headline has a 3-part action series after "where you "
    final lower = headline.toLowerCase();
    final whereIdx = lower.indexOf('where you ');
    if (whereIdx != -1) {
      final afterWhere = headline.substring(whereIdx + 'where you '.length).trim();
      final parts = afterWhere
          .split(_goalClauseSplitRegex)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length >= 3) {
        return List.generate(3, (i) {
          final rawClause = parts[i];
          final formattedClause = rawClause[0].toUpperCase() + rawClause.substring(1);
          final body = formattedClause.endsWith('.')
              ? formattedClause
              : '$formattedClause.';
          // Pair with Core Loop Beat title when available, else derive a 2-3 word label
          String title = _deriveShortClauseLabel(rawClause, i);
          if (i < coreLoopBeats.length && coreLoopBeats[i].contains(':')) {
            final beatTitle = coreLoopBeats[i].split(':').first.trim();
            if (beatTitle.isNotEmpty && beatTitle.length <= 24) {
              title = beatTitle;
            }
          }
          return (title: title, body: body);
        });
      }
    }

    // 2. Otherwise pull the top 3 Core Loop Beats (`Title: Action description`)
    final result = <({String title, String body})>[];
    for (var i = 0; i < coreLoopBeats.length && result.length < 3; i++) {
      final beat = coreLoopBeats[i].trim();
      if (beat.isEmpty) continue;
      final colon = beat.indexOf(':');
      if (colon > 0 && colon < beat.length - 1) {
        result.add((
          title: beat.substring(0, colon).trim(),
          body: beat.substring(colon + 1).trim(),
        ));
      } else {
        result.add((
          title: 'Step 0${i + 1}',
          body: beat,
        ));
      }
    }
    return result;
  }

  String _deriveShortClauseLabel(String clause, int index) {
    final lower = clause.toLowerCase();
    if (lower.contains('plant') && lower.contains('harvest')) {
      return 'Plant & Harvest';
    }
    if (lower.contains('sell') || lower.contains('ammo') || lower.contains('load')) {
      return 'Load or Sell';
    }
    if (lower.contains('wave') || lower.contains('arena')) {
      return 'Arena Run';
    }
    final words = clause
        .replaceAll(_nonWordStripRegex, '')
        .split(_whitespaceRegex)
        .where((w) => w.isNotEmpty)
        .take(3)
        .toList();
    if (words.isEmpty) return 'Phase 0${index + 1}';
    return words.join(' ');
  }

  Widget _buildCalloutStatement(
    String statement, {
    required bool highlightMetrics,
    VoidCallback? onEditTap,
  }) {
    final barColor = highlightMetrics ? accentEmerald : accentCyan;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEditTap,
        child: Container(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8, right: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: barColor,
                width: 3,
              ),
            ),
          ),
          child: highlightMetrics
              ? buildMetricHighlightedRichText(
                  statement,
                  usePill: true,
                  fontSize: 15,
                  height: 1.58,
                )
              : Text(
                  statement,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.58,
                    color: textPrimary,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildKvSpecGrid({
    required bool isGameSpec,
    required List<String> keys,
    required List<String> values,
  }) {
    final pairs = List.generate(keys.length, (i) {
      final val = i < values.length ? values[i] : '—';
      return MapEntry(keys[i], val);
    });

    return Container(
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildKvCell(
                    isGameSpec: isGameSpec,
                    cellIndex: 0,
                    k: pairs[0].key,
                    v: pairs[0].value,
                    rightBorder: true,
                    bottomBorder: true,
                  ),
                ),
                Expanded(
                  child: _buildKvCell(
                    isGameSpec: isGameSpec,
                    cellIndex: 1,
                    k: pairs[1].key,
                    v: pairs[1].value,
                    rightBorder: false,
                    bottomBorder: true,
                  ),
                ),
              ],
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildKvCell(
                    isGameSpec: isGameSpec,
                    cellIndex: 2,
                    k: pairs[2].key,
                    v: pairs[2].value,
                    rightBorder: true,
                    bottomBorder: false,
                  ),
                ),
                Expanded(
                  child: _buildKvCell(
                    isGameSpec: isGameSpec,
                    cellIndex: 3,
                    k: pairs[3].key,
                    v: pairs[3].value,
                    rightBorder: false,
                    bottomBorder: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKvCell({
    required bool isGameSpec,
    required int cellIndex,
    required String k,
    required String v,
    required bool rightBorder,
    required bool bottomBorder,
  }) {
    return Material(
      color: bgSurface,
      child: InkWell(
        onTap: () => _showDirectKvEditDialog(
          isGameSpec: isGameSpec,
          cellIndex: cellIndex,
          label: k,
          currentValue: v,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              right: rightBorder ? BorderSide(color: borderSubtle) : BorderSide.none,
              bottom: bottomBorder ? BorderSide(color: borderSubtle) : BorderSide.none,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    k,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: textSecondary.withValues(alpha: 0.85),
                    ),
                  ),
                  Icon(
                    Icons.edit_outlined,
                    size: 11,
                    color: textMuted.withValues(alpha: 0.65),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                v.trim().isEmpty ? 'Click to set...' : v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: v.trim().isEmpty ? FontWeight.w500 : FontWeight.w700,
                  fontStyle: v.trim().isEmpty ? FontStyle.italic : FontStyle.normal,
                  color: v.trim().isEmpty ? textMuted : textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Splits `"Lead-In Label: Description text"` so the lead-in before `:` is bold & bright
  /// and the description after `:` is slightly muted for instant scanability.
  Widget _buildFormattedLeadInText(String rawText) {
    final colonIdx = rawText.indexOf(':');
    if (colonIdx <= 0 || colonIdx >= rawText.length - 1) {
      return Text(
        rawText,
        style: GoogleFonts.inter(
          fontSize: 13.5,
          height: 1.45,
          color: textPrimary,
        ),
      );
    }

    final leadIn = rawText.substring(0, colonIdx + 1);
    final rest = rawText.substring(colonIdx + 1);

    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 13.5,
          height: 1.45,
        ),
        children: [
          TextSpan(
            text: leadIn,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          TextSpan(
            text: rest,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 04: Open Editorial Hairline-Divided Design Pillars + Inline Add/Delete ──
  Widget _buildDesignPillarCards(
    ProjectConceptBlueprint draft, {
    bool isReadOnlySummary = false,
  }) {
    final pillars = draft.designPillars;

    Widget buildPillarRow(int idx) {
      final raw = pillars[idx];
      final parsedPillar =
          ProjectConceptBlueprint.parsePillarTitleAndBody(raw, idx);
      final String title = parsedPillar.title;
      final String body = parsedPillar.body;

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDirectSectionTextEditDialog(
            title: 'P·${(idx + 1).toString().padLeft(2, '0')} Design Pillar',
            initialText: '${parsedPillar.title}: ${parsedPillar.body}',
            onSave: (val) => widget.workbench.updateConceptDraft((d) {
              final next = List<String>.from(d.designPillars);
              next[idx] = ProjectConceptBlueprint.ensureNamedPillar(val, idx);
              d.designPillars = next;
            }),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'P·${(idx + 1).toString().padLeft(2, '0')}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: accentCyan,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.displayFont(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.42,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isReadOnlySummary && pillars.length > 1) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => widget.workbench.updateConceptDraft((d) {
                      final next = List<String>.from(d.designPillars)..removeAt(idx);
                      d.designPillars = next;
                    }),
                    borderRadius: BorderRadius.circular(3),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      child: Text(
                        '×',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < pillars.length; i++) buildPillarRow(i),
        if (!isReadOnlySummary) ...[
          const SizedBox(height: 10),
          _buildInlineAddBar(
            label: '+ Add a custom Design Pillar...',
            onTap: () => _showDirectSectionTextEditDialog(
              title: 'Add Design Pillar',
              initialText: 'Every Choice Echoes: Player actions leave visible feedback in the arena.',
              onSave: (val) => widget.workbench.updateConceptDraft((d) {
                d.designPillars = [
                  ...d.designPillars,
                  ProjectConceptBlueprint.ensureNamedPillar(
                    val,
                    d.designPillars.length,
                  ),
                ];
              }),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInlineAddBar({
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgRecessed.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: borderSubtle),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: textMuted,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bgSurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderBright),
                ),
                child: Text(
                  '+ Add',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIndexedRows({
    required String prefix,
    required List<String> items,
    required bool isCoreLoop,
    void Function(int index, String newValue)? onEditItem,
    void Function(int oldIndex, int newIndex)? onReorderItem,
    void Function(int index)? onDeleteItem,
    VoidCallback? onAddItem,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onEditItem == null
                  ? null
                  : () => _showDirectSectionTextEditDialog(
                        title: '$prefix·${(i + 1).toString().padLeft(2, '0')}',
                        initialText: items[i],
                        onSave: (val) => onEditItem(i, val),
                      ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: borderSubtle),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 68,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1.5),
                        child: Text(
                          '$prefix·${(i + 1).toString().padLeft(2, '0')}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: accentCyan,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildFormattedLeadInText(items[i]),
                    ),
                    if (onReorderItem != null && items.length > 1) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        key: ValueKey('core_loop_move_up_$i'),
                        onTap: i > 0 ? () => onReorderItem(i, i - 1) : null,
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          child: Text(
                            '↑',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: i > 0
                                  ? textSecondary
                                  : textMuted.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        key: ValueKey('core_loop_move_down_$i'),
                        onTap: i < items.length - 1
                            ? () => onReorderItem(i, i + 1)
                            : null,
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          child: Text(
                            '↓',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: i < items.length - 1
                                  ? textSecondary
                                  : textMuted.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (onDeleteItem != null) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => onDeleteItem(i),
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          child: Text(
                            '×',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: textMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
        if (isCoreLoop && items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                '↺ Loops back to BEAT·01 (Continuous Cycle)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: accentCyan,
                ),
              ),
            ),
          ),
        ],
        if (onAddItem != null) ...[
          const SizedBox(height: 10),
          _buildInlineAddBar(
            label: isCoreLoop
                ? '+ Add a custom Core Loop Beat...'
                : '+ Add item...',
            onTap: onAddItem,
          ),
        ],
      ],
    );
  }

  Widget _buildTradeOffSplitBars(
    List<String> tradeOffs, {
    void Function(int index, String newValue)? onEditItem,
    void Function(int index)? onDeleteItem,
    VoidCallback? onAddItem,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < tradeOffs.length; i++) ...[
          _buildSingleTradeOffBar(
            tradeOffs[i],
            onTap: onEditItem == null
                ? null
                : () => _showDirectSectionTextEditDialog(
                      title: 'Trade-Off #${i + 1} (X over Y)',
                      initialText: tradeOffs[i],
                      onSave: (val) => onEditItem(i, val),
                    ),
            onDelete: onDeleteItem == null ? null : () => onDeleteItem(i),
          ),
        ],
        if (onAddItem != null) ...[
          const SizedBox(height: 10),
          _buildInlineAddBar(
            label: '+ Add a custom Trade-Off (X over Y)...',
            onTap: onAddItem,
          ),
        ],
      ],
    );
  }

  Widget _buildSingleTradeOffBar(
    String rawRule, {
    VoidCallback? onTap,
    VoidCallback? onDelete,
  }) {
    final clean = rawRule.replaceFirst(_prioritizePrefixRegex, '');
    final parts = clean.split(_overSplitRegex);
    final winText = parts.isNotEmpty ? parts[0].trim() : clean;
    final loseText = parts.length > 1 ? parts.sublist(1).join(' over ').trim() : 'secondary complexity';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: borderSubtle),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(
                  '✓ WIN',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accentEmerald,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  winText,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'OVER',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  loseText,
                  textAlign: TextAlign.left,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    color: textSecondary.withValues(alpha: 0.78),
                    decoration: TextDecoration.lineThrough,
                    decorationColor: accentCrimson.withValues(alpha: 0.70),
                    decorationThickness: 1.6,
                  ),
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    child: Text(
                      '×',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCutGuardrailChips(
    List<String> exclusions, {
    void Function(int index, String newValue)? onEditItem,
    void Function(int index)? onDeleteItem,
    VoidCallback? onAddItem,
  }) {
    Widget buildExclusionRow(int idx) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEditItem == null
              ? null
              : () => _showDirectSectionTextEditDialog(
                    title: 'Out of Scope Exclusion #${idx + 1}',
                    initialText: exclusions[idx],
                    onSave: (val) => onEditItem(idx, val),
                  ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    '✕ CUT',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: accentCrimson,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exclusions[idx],
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: textSecondary.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                if (onDeleteItem != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => onDeleteItem(idx),
                    borderRadius: BorderRadius.circular(3),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      child: Text(
                        '×',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < exclusions.length; i++) buildExclusionRow(i),
        if (onAddItem != null) ...[
          const SizedBox(height: 10),
          _buildInlineAddBar(
            label: '+ Add an Out of Scope exclusion (Cut)...',
            onTap: onAddItem,
          ),
        ],
      ],
    );
  }

}
