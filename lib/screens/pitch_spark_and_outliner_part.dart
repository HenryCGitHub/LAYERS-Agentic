part of 'project_pitch_screen.dart';

extension _PitchSparkAndOutlinerExt on _ProjectPitchScreenState {
  static const int _kSparkMaxCharsPerLine = 80;

  // ── Single-Input 80-Character Word Document Composer + Progress Animation (00 · PITCH & CONCEPT) ──
  Widget _buildInitialSparkLauncher() {
    final intake = widget.workbench.sparkIntake;
    final isBusy = widget.workbench.isAgentBusy;
    final progressStep = widget.workbench.agentProgressStep;

    // Word Document Editor Geometry:
    // Width is computed directly from the 80-character count and current font size
    // plus generous horizontal document margins so 80 chars/line always fills the width.
    final double pitchFontSize =
        _isMobileMeasure ? 15.0 : (_isTabletMeasure ? 16.5 : 18.0);
    final double docPadX =
        _isMobileMeasure ? 24.0 : (_isTabletMeasure ? 40.0 : 64.0);
    final double docMaxWidth =
        (_kSparkMaxCharsPerLine * 0.515 * pitchFontSize) + (2 * docPadX);

    final bool hasSubmittedIdea =
        intake != null && intake.effectiveSummary.trim().isNotEmpty;
    final String rawInputText = _sparkController.text.trim();
    final bool hasInputText = rawInputText.isNotEmpty;

    Future<void> submitOrRefineIdea() async {
      if (isBusy) return;
      final singleLineInput = _sparkController.text
          .replaceAll(_newlineCollapseRegex, ' ')
          .trim();
      if (singleLineInput.isEmpty && !hasSubmittedIdea) return;

      final previousSummary = intake?.baseSummary;
      _rebuild(() {
        if (previousSummary != null && previousSummary.trim().isNotEmpty) {
          _sparkUndoStack.add(previousSummary);
        }
        _activeCustomChipIndex = null;
        _sparkController.clear();
      });

      final promptToSend = singleLineInput.isNotEmpty
          ? singleLineInput
          : (intake?.baseSummary ?? '');
      await widget.workbench.ingestOrRefineSparkIdea(promptToSend);
    }

    void revertUndo() {
      if (_sparkUndoStack.isEmpty || intake == null || isBusy) return;
      _rebuild(() {
        intake.baseSummary = _sparkUndoStack.removeLast();
        intake.syncChipsWithSummary();
        _activeCustomChipIndex = null;
      });
    }

    Future<void> generateConceptBlueprint() async {
      if (isBusy) return;
      final unsubmittedInput = _sparkController.text
          .replaceAll(_newlineCollapseRegex, ' ')
          .trim();
      if (!hasSubmittedIdea && unsubmittedInput.isEmpty) return;

      // Zero-loss safeguard: if user typed in the input box and clicked Generate directly,
      // fold their unsubmitted text into the pitch automatically.
      final String effectivePitch;
      if (hasSubmittedIdea && unsubmittedInput.isNotEmpty) {
        effectivePitch = '${intake.canonicalPrompt}. $unsubmittedInput';
      } else if (hasSubmittedIdea) {
        effectivePitch = intake.canonicalPrompt;
      } else {
        effectivePitch = unsubmittedInput;
      }
      _sparkController.clear();
      await widget.workbench.startConceptInterview(effectivePitch, true);
    }

    final String dynamicTooltipMessage = hasSubmittedIdea
        ? 'Input to refine your pitch (Enter to submit · Shift+Enter for new line · 80 chars/line)'
        : 'Input your game idea (Enter to submit · Shift+Enter for new line · 80 chars/line)';
    final String dynamicHintText = hasSubmittedIdea
        ? 'Input to refine (Enter to submit · Shift+Enter for new line)...'
        : 'Input your game idea (Enter to submit · Shift+Enter for new line)...';

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: docMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header Meta Row: "00 · PITCH & CONCEPT" + "[Saved Projects ▾]" ──
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      hasSubmittedIdea && intake.workingTitle.trim().isNotEmpty
                          ? '00 · PITCH & CONCEPT · ${intake.workingTitle.toUpperCase()}'
                          : '00 · PITCH & CONCEPT',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: isDark ? const Color(0xFF646D7D) : textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.workbench.savedProjects.isNotEmpty)
                    PopupMenuButton<String>(
                      key: const ValueKey('saved_projects_dropdown_btn'),
                      tooltip: 'Saved Projects',
                      color: bgSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: borderBright),
                      ),
                      onSelected: (projectId) {
                        widget.workbench.switchProject(projectId);
                      },
                      itemBuilder: (ctx) => [
                        for (final p in widget.workbench.savedProjects)
                          PopupMenuItem<String>(
                            key: ValueKey('spark_resume_project_${p.id}'),
                            value: p.id,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    p.title,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Resume →',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          'Saved Projects ▾',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF9CA3AF) : textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Single Word-Document Greyscale Composer Box (ONLY ONE INPUT AREA) ──
            Container(
              key: const ValueKey('spark_composer_card'),
              decoration: BoxDecoration(
                color: bgSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderSubtle),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Work-In-Progress Top Indeterminate Bar (Visible while AI is working)
                  if (isBusy)
                    LinearProgressIndicator(
                      key: const ValueKey('spark_busy_progress_bar'),
                      minHeight: 3,
                      backgroundColor: borderSubtle,
                      valueColor: AlwaysStoppedAnimation<Color>(textPrimary),
                    ),

                  // Submitted Pitch Document Display with Google ImageFX-Style Dynamic Expressive Chips
                  if (hasSubmittedIdea)
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: isBusy ? 0.45 : 1.0,
                      child: Container(
                        key: const ValueKey('spark_committed_pitch_text'),
                        padding: EdgeInsets.fromLTRB(
                          docPadX,
                          28,
                          docPadX,
                          22,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: borderSubtle),
                          ),
                        ),
                        child: _buildCommittedPitchWithExpressiveChips(
                          intake: intake,
                          pitchFontSize: pitchFontSize,
                          isBusy: isBusy,
                        ),
                      ),
                    ),

                  // Live Work-In-Progress Status Banner (Visible while AI is working)
                  if (isBusy)
                    Padding(
                      key: const ValueKey('spark_busy_progress_banner'),
                      padding: EdgeInsets.fromLTRB(docPadX, 16, docPadX, 0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(textPrimary),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              progressStep ??
                                  (hasSubmittedIdea
                                      ? 'Refining your pitch...'
                                      : 'Summarizing your game idea...'),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // THE ONLY INPUT AREA (Switches from "Input your game idea..." -> "Input to refine...")
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: docPadX,
                      vertical: hasSubmittedIdea ? 18 : 28,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Tooltip(
                            key: const ValueKey('spark_pitch_tooltip'),
                            message: dynamicTooltipMessage,
                            child: Focus(
                              onKeyEvent: (node, event) {
                                if ((event is KeyDownEvent ||
                                        event is KeyRepeatEvent) &&
                                    (event.logicalKey ==
                                            LogicalKeyboardKey.enter ||
                                        event.logicalKey ==
                                            LogicalKeyboardKey.numpadEnter) &&
                                    (HardwareKeyboard
                                            .instance.isMetaPressed ||
                                        HardwareKeyboard
                                            .instance.isControlPressed)) {
                                  generateConceptBlueprint();
                                  return KeyEventResult.handled;
                                }
                                return _handleMultilinePitchKeyEvent(
                                  event,
                                  _sparkController,
                                  onSubmit: submitOrRefineIdea,
                                );
                              },
                              child: TextField(
                                key: const ValueKey('spark_input_field'),
                                controller: _sparkController,
                                focusNode: _sparkFocusNode,
                                minLines: hasSubmittedIdea ? 1 : 3,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                inputFormatters: const [
                                  MaxColumnLineWrapFormatter(
                                    maxCharsPerLine: _kSparkMaxCharsPerLine,
                                  ),
                                ],
                                onChanged: (_) => _rebuild(),
                                style: GoogleFonts.inter(
                                  fontSize: pitchFontSize,
                                  height: 1.65,
                                  color: textPrimary,
                                ),
                                decoration: InputDecoration(
                                  filled: false,
                                  isCollapsed: true,
                                  hintMaxLines: hasSubmittedIdea ? 1 : 3,
                                  hintText: dynamicHintText,
                                  hintStyle: GoogleFonts.inter(
                                    fontSize: pitchFontSize,
                                    height: 1.65,
                                    color: textMuted,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: (_) => submitOrRefineIdea(),
                              ),
                            ),
                          ),
                        ),
                        if (_sparkUndoStack.isNotEmpty && !isBusy) ...[
                          const SizedBox(width: 10),
                          InkWell(
                            key: const ValueKey('spark_undo_btn'),
                            onTap: revertUndo,
                            borderRadius: BorderRadius.circular(5),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Text(
                                'Undo',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFF9CA3AF)
                                      : textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Tooltip(
                          message: hasSubmittedIdea
                              ? 'Refine pitch (Return)'
                              : 'Submit game idea (Return)',
                          child: InkWell(
                            key: const ValueKey('ingest_idea_summary_btn'),
                            onTap: (!isBusy &&
                                    (hasInputText || hasSubmittedIdea))
                                ? submitOrRefineIdea
                                : null,
                            borderRadius: BorderRadius.circular(7),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: isBusy
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          textPrimary,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      '↵',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        height: 1.0,
                                        color: (hasInputText ||
                                                hasSubmittedIdea)
                                            ? (hasInputText
                                                ? textPrimary
                                                : textSecondary)
                                            : textMuted.withValues(alpha: 0.4),
                                      ),
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

            // ── Separated Primary Stage-Gate CTA (10% Emerald Primary Action) ──
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  key: const ValueKey('direct_generate_blueprint_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF06281E),
                    disabledBackgroundColor:
                        textMuted.withValues(alpha: 0.22),
                    disabledForegroundColor:
                        textMuted.withValues(alpha: 0.55),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    elevation: 0,
                  ),
                  onPressed:
                      (!isBusy && (hasSubmittedIdea || hasInputText))
                          ? generateConceptBlueprint
                          : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isBusy) ...[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF06281E),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        isBusy
                            ? 'Generating Blueprint (01–08)...'
                            : 'Generate Concept Blueprint →',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
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
    );
  }

  // ── Google ImageFX-Style Dynamic Expressive Chips Renderer (60-30-10 & Greyscale Calibrated) ──
  Widget _buildCommittedPitchWithExpressiveChips({
    required SparkIdeaIntakeResult intake,
    required double pitchFontSize,
    required bool isBusy,
  }) {
    final fullText = intake.effectiveSummary.trim();
    final proseStyle = GoogleFonts.inter(
      fontSize: pitchFontSize,
      height: 1.75,
      color: textPrimary,
    );

    final chips = intake.expressiveChips;
    if (chips.isEmpty) {
      return SelectableText(fullText, style: proseStyle);
    }

    final lowerText = fullText.toLowerCase();
    final matchedSpans = <(int start, int end, int chipIndex)>[];

    bool overlapsMatched(int start, int end) {
      for (final (s, e, _) in matchedSpans) {
        if (start < e && end > s) return true;
      }
      return false;
    }

    for (int i = 0; i < chips.length; i++) {
      final phrase = chips[i].currentValue.trim();
      if (phrase.isEmpty) continue;
      final idx = lowerText.indexOf(phrase.toLowerCase());
      if (idx < 0) continue;
      final end = idx + phrase.length;
      if (overlapsMatched(idx, end)) continue;
      matchedSpans.add((idx, end, i));
    }

    if (matchedSpans.isEmpty) {
      return SelectableText(fullText, style: proseStyle);
    }

    matchedSpans.sort((a, b) => a.$1.compareTo(b.$1));

    final inlineSpans = <InlineSpan>[];
    int cursor = 0;
    for (final (start, end, chipIndex) in matchedSpans) {
      if (start > cursor) {
        inlineSpans.add(
          TextSpan(
            text: fullText.substring(cursor, start),
            style: proseStyle,
          ),
        );
      }
      final exactSlice = fullText.substring(start, end);
      inlineSpans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildExpressiveChipPill(
            intake: intake,
            chipIndex: chipIndex,
            chip: chips[chipIndex],
            displayLabel: exactSlice,
            pitchFontSize: pitchFontSize,
            isBusy: isBusy,
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < fullText.length) {
      inlineSpans.add(
        TextSpan(
          text: fullText.substring(cursor),
          style: proseStyle,
        ),
      );
    }

    final activeCustomIdx = _activeCustomChipIndex;
    final hasValidCustomBar =
        activeCustomIdx != null && activeCustomIdx < chips.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(children: inlineSpans),
        ),
        if (hasValidCustomBar) ...[
          const SizedBox(height: 14),
          _buildCustomChipInlineBar(
            intake: intake,
            chipIndex: activeCustomIdx,
            chip: chips[activeCustomIdx],
          ),
        ],
      ],
    );
  }

  Widget _buildExpressiveChipPill({
    required SparkIdeaIntakeResult intake,
    required int chipIndex,
    required SparkExpressiveChip chip,
    required String displayLabel,
    required double pitchFontSize,
    required bool isBusy,
  }) {
    // 60-30-10 & Greyscale Calibration:
    // - At rest: 30% structural elevation (#1B202C fill, #2E3646 border, crisp #F9FAFB text + #9CA3AF caret)
    // - Modified: 10% intentional Emerald accent (#10B981 border/tint) matching Stage-Gate CTA
    const emeraldAccent = Color(0xFF10B981);
    final isModified = chip.isModified;
    final pillBg = isModified
        ? emeraldAccent.withValues(alpha: isDark ? 0.14 : 0.10)
        : (isDark ? const Color(0xFF1B202C) : bgRecessed);
    final pillBorder = isModified
        ? emeraldAccent.withValues(alpha: 0.65)
        : (isDark ? const Color(0xFF2E3646) : borderBright);
    final pillTextColor = isModified
        ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
        : textPrimary;
    final caretColor = isModified ? emeraldAccent : textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: PopupMenuButton<String>(
        key: ValueKey('spark_expressive_chip_$chipIndex'),
        enabled: !isBusy,
        tooltip: '${chip.category} · Click to swap keyword',
        color: bgSurface,
        elevation: 8,
        offset: const Offset(0, 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderBright),
        ),
        onSelected: (selectedValue) {
          if (selectedValue == '__custom__') {
            _rebuild(() {
              _activeCustomChipIndex = chipIndex;
              _customChipController.text = chip.currentValue;
            });
            return;
          }
          if (selectedValue.toLowerCase() ==
              chip.currentValue.toLowerCase()) {
            return;
          }
          final prevSummary = intake.baseSummary;
          final changed = widget.workbench.replaceSparkExpressiveChip(
            chipIndex,
            selectedValue,
          );
          if (changed) {
            _rebuild(() {
              _sparkUndoStack.add(prevSummary);
              _activeCustomChipIndex = null;
            });
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem<String>(
            enabled: false,
            height: 28,
            child: Text(
              '0${chipIndex + 1} · ${chip.category}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: textMuted,
              ),
            ),
          ),
          for (int optIdx = 0; optIdx < chip.alternatives.length; optIdx++)
            PopupMenuItem<String>(
              key: ValueKey('spark_chip_option_${chipIndex}_$optIdx'),
              value: chip.alternatives[optIdx],
              height: 38,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 18,
                    child: chip.alternatives[optIdx].toLowerCase() ==
                            chip.currentValue.toLowerCase()
                        ? const Text(
                            '✓',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: emeraldAccent,
                            ),
                          )
                        : null,
                  ),
                  Flexible(
                    child: Text(
                      chip.alternatives[optIdx],
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: chip.alternatives[optIdx].toLowerCase() ==
                                chip.currentValue.toLowerCase()
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: chip.alternatives[optIdx].toLowerCase() ==
                                chip.currentValue.toLowerCase()
                            ? textPrimary
                            : textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            key: ValueKey('spark_chip_custom_$chipIndex'),
            value: '__custom__',
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 18, child: Text('✎')),
                Text(
                  '+ Custom phrase...',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: pillBorder, width: 1.1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayLabel,
                style: GoogleFonts.inter(
                  fontSize: pitchFontSize - 1.0,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: pillTextColor,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '▾',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: caretColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomChipInlineBar({
    required SparkIdeaIntakeResult intake,
    required int chipIndex,
    required SparkExpressiveChip chip,
  }) {
    void commitCustomPhrase() {
      final clean = _customChipController.text.trim();
      if (clean.isEmpty) {
        _rebuild(() => _activeCustomChipIndex = null);
        return;
      }
      final prevSummary = intake.baseSummary;
      final changed = widget.workbench.replaceSparkExpressiveChip(
        chipIndex,
        clean,
      );
      _rebuild(() {
        if (changed) {
          _sparkUndoStack.add(prevSummary);
        }
        _activeCustomChipIndex = null;
      });
    }

    void cancelCustomPhrase() {
      _rebuild(() => _activeCustomChipIndex = null);
    }

    return Container(
      key: ValueKey('spark_chip_custom_bar_$chipIndex'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderBright),
      ),
      child: Row(
        children: [
          Text(
            '${chip.category}:',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: ValueKey('spark_chip_custom_input_$chipIndex'),
              controller: _customChipController,
              autofocus: true,
              style: GoogleFonts.inter(fontSize: 14, color: textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Type custom ${chip.category.toLowerCase()} phrase...',
                hintStyle: GoogleFonts.inter(fontSize: 13.5, color: textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
              onSubmitted: (_) => commitCustomPhrase(),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            key: ValueKey('spark_chip_custom_save_$chipIndex'),
            onTap: commitCustomPhrase,
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '✓ Apply',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF10B981),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            key: ValueKey('spark_chip_custom_cancel_$chipIndex'),
            onTap: cancelCustomPhrase,
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '×',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
