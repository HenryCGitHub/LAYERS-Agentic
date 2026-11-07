part of 'project_pitch_screen.dart';

extension _PitchSparkAndOutlinerExt on _ProjectPitchScreenState {
  static const int _kSparkMaxCharsPerLine = 80;
  static const Set<String> _kSparkNudgeSeeds = {
    'twist:',
    'camera and engine:',
    'core action:',
  };

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
      // A bare nudge seed (e.g. "Twist:") has no answer yet; keep it in the box.
      if (_kSparkNudgeSeeds.contains(singleLineInput.toLowerCase())) return;

      final previousSummary = intake?.baseSummary;
      _rebuild(() {
        if (previousSummary != null && previousSummary.trim().isNotEmpty) {
          _sparkUndoStack.add(previousSummary);
        }
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
        // The nudge belongs to the newer summary; the next refine recomputes it.
        intake.missing = null;
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

    final String wrappedCommittedSummary = hasSubmittedIdea
        ? MaxColumnLineWrapFormatter.wrapTextAtColumn(
            intake.effectiveSummary.trim(),
            maxCharsPerLine: _kSparkMaxCharsPerLine,
          )
        : '';

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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Subtle Cloud Sync Indicator
                      Tooltip(
                        message: widget.workbench.isCloudSynced
                            ? 'Synced to Firebase Cloud'
                            : 'Saved to Local Vault',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: widget.workbench.isCloudSynced
                                  ? const Color(0xFF10B981).withValues(alpha: 0.25)
                                  : borderSubtle,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.workbench.isCloudSynced
                                      ? const Color(0xFF10B981)
                                      : textMuted,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.workbench.isCloudSynced
                                    ? 'Synced'
                                    : 'Local',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: widget.workbench.isCloudSynced
                                      ? const Color(0xFF10B981)
                                      : textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.workbench.savedProjects.isNotEmpty) ...[
                        const SizedBox(width: 6),
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
                              horizontal: 5,
                              vertical: 3,
                            ),
                            child: Text(
                              'Projects ▾',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFF9CA3AF) : textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
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

                  // Submitted Pitch Document Display (Plain Document Text, NOT a 2nd Input Box!)
                  if (hasSubmittedIdea)
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: isBusy ? 0.45 : 1.0,
                      child: Container(
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
                        child: SelectableText(
                          wrappedCommittedSummary,
                          key: const ValueKey('spark_committed_pitch_text'),
                          style: GoogleFonts.inter(
                            fontSize: pitchFontSize,
                            height: 1.65,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ),

                  // "What's missing" nudge: only when Gemini checked (`missing != null`)
                  if (hasSubmittedIdea && !isBusy && intake.missing != null)
                    _buildMissingNudgeRow(intake.missing!, docPadX),

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

  // ── "What's Missing" Nudge Row (plain text buttons, no pills) ──
  Widget _buildMissingNudgeRow(List<SparkMissingPiece> missing, double docPadX) {
    final labelStyle = GoogleFonts.jetBrainsMono(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: textMuted,
    );
    return Container(
      key: const ValueKey('spark_missing_nudge'),
      padding: EdgeInsets.symmetric(horizontal: docPadX, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderSubtle)),
      ),
      child: missing.isEmpty
          ? Text(
              '✓ Action, twist, and setup covered',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF10B981),
              ),
            )
          : Wrap(
              spacing: 16,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('MISSING', style: labelStyle),
                for (final piece in missing)
                  InkWell(
                    key: ValueKey('spark_missing_${piece.kind}'),
                    onTap: () {
                      _sparkController.value = TextEditingValue(
                        text: piece.seed,
                        selection:
                            TextSelection.collapsed(offset: piece.seed.length),
                      );
                      _sparkFocusNode.requestFocus();
                      _rebuild();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: textMuted),
                        ),
                      ),
                      child: Text(
                        '${piece.kind} · ${piece.question}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
