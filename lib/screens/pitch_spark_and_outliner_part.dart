part of 'project_pitch_screen.dart';

extension _PitchSparkAndOutlinerExt on _ProjectPitchScreenState {
  static const int _kSparkMaxCharsPerLine = 80;

  // ── 80-Character Word Document Pitch & Concept Composer (00 · PITCH & CONCEPT) ──
  Widget _buildInitialSparkLauncher() {
    final intake = widget.workbench.sparkIntake;
    final isBusy = widget.workbench.isAgentBusy;

    // Word Document Editor Geometry:
    // Width is computed directly from the 80-character count and current font size
    // plus generous horizontal document margins so 80 chars/line always fills the width.
    final double pitchFontSize =
        _isMobileMeasure ? 15.0 : (_isTabletMeasure ? 16.5 : 18.0);
    final double refineFontSize =
        _isMobileMeasure ? 14.5 : (_isTabletMeasure ? 15.0 : 16.0);
    final double docPadX =
        _isMobileMeasure ? 24.0 : (_isTabletMeasure ? 40.0 : 64.0);
    final double docMaxWidth =
        (_kSparkMaxCharsPerLine * 0.515 * pitchFontSize) + (2 * docPadX);

    final String currentPitch = _sparkController.text.trim();
    final String currentTweak = _sparkTweakController.text.trim();
    final bool hasPitchContent = currentPitch.isNotEmpty;
    final bool hasTweakContent = currentTweak.isNotEmpty;

    Future<void> refinePitchInPlace() async {
      if (isBusy) return;
      final rawPitch = _sparkController.text.trim();
      final rawTweak = _sparkTweakController.text.trim();

      // If top pitch box is empty and user typed their idea into the bottom bar, promote it to the top box.
      if (rawPitch.isEmpty && rawTweak.isNotEmpty) {
        final wrapped = MaxColumnLineWrapFormatter.wrapTextAtColumn(
          rawTweak,
          maxCharsPerLine: _kSparkMaxCharsPerLine,
        );
        _rebuild(() {
          _sparkController.value = TextEditingValue(
            text: wrapped,
            selection: TextSelection.collapsed(offset: wrapped.length),
          );
          _sparkTweakController.clear();
        });
        return;
      }

      if (rawPitch.isEmpty) return;

      final previousText = _sparkController.text;
      final singleLinePitch =
          rawPitch.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
      final singleLineTweak =
          rawTweak.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();

      _rebuild(() {
        _sparkUndoStack.add(previousText);
        _sparkTweakController.clear();
      });

      if (widget.workbench.sparkIntake == null) {
        final combinedInput = singleLineTweak.isNotEmpty
            ? '$singleLinePitch. $singleLineTweak'
            : singleLinePitch;
        await widget.workbench.ingestOrRefineSparkIdea(combinedInput);
      } else {
        final refineInput =
            singleLineTweak.isNotEmpty ? singleLineTweak : singleLinePitch;
        await widget.workbench.ingestOrRefineSparkIdea(refineInput);
      }

      if (!mounted) return;
      final updatedSummary = widget.workbench.sparkIntake?.effectiveSummary;
      if (updatedSummary != null && updatedSummary.trim().isNotEmpty) {
        final wrapped = MaxColumnLineWrapFormatter.wrapTextAtColumn(
          updatedSummary.trim(),
          maxCharsPerLine: _kSparkMaxCharsPerLine,
        );
        _rebuild(() {
          _sparkController.value = TextEditingValue(
            text: wrapped,
            selection: TextSelection.collapsed(offset: wrapped.length),
          );
        });
      }
    }

    void revertUndo() {
      if (_sparkUndoStack.isEmpty) return;
      _rebuild(() {
        final restored = _sparkUndoStack.removeLast();
        _sparkController.value = TextEditingValue(
          text: restored,
          selection: TextSelection.collapsed(offset: restored.length),
        );
      });
    }

    Future<void> generateConceptBlueprint() async {
      if (isBusy) return;
      final rawPitch = _sparkController.text
          .replaceAll(RegExp(r'\s*\n\s*'), ' ')
          .trim();
      final rawTweak = _sparkTweakController.text
          .replaceAll(RegExp(r'\s*\n\s*'), ' ')
          .trim();
      if (rawPitch.isEmpty && rawTweak.isEmpty) return;

      // Zero-loss safeguard: if user typed a refinement and clicked Generate directly, fold it in.
      final effectivePitch = (rawPitch.isNotEmpty && rawTweak.isNotEmpty)
          ? '$rawPitch. $rawTweak'
          : (rawPitch.isNotEmpty ? rawPitch : rawTweak);
      _sparkTweakController.clear();
      await widget.workbench.startConceptInterview(effectivePitch, true);
    }

    final String topTooltipMessage = hasPitchContent
        ? 'Input to refine in the bar below, or edit your pitch text directly'
        : 'Input your game idea (a 4-word spark or a full pasted GDD)';
    final String refineTooltipMessage = hasPitchContent
        ? 'Input to refine your pitch (Enter to submit · Shift+Enter for new line · 80 chars/line)'
        : 'Input your game idea above first';
    final String refineHintText = hasPitchContent
        ? 'Input to refine (Enter to submit · Shift+Enter for new line)...'
        : 'Input your game idea above first...';

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
                      intake != null && intake.workingTitle.trim().isNotEmpty
                          ? '00 · PITCH & CONCEPT · ${intake.workingTitle.toUpperCase()}'
                          : '00 · PITCH & CONCEPT',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: textSecondary,
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderSubtle),
                        ),
                        child: Text(
                          'Saved Projects ▾',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Single Word-Document Greyscale Composer Box ──
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
                  // Dynamic Status / Tooltip Hint Row
                  Padding(
                    padding: EdgeInsets.fromLTRB(docPadX, 24, docPadX, 0),
                    child: Text(
                      hasPitchContent
                          ? 'Input to refine below, or edit pitch directly'
                          : 'Input your game idea to get started',
                      key: const ValueKey('spark_dynamic_tooltip_label'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: hasPitchContent ? textSecondary : textMuted,
                      ),
                    ),
                  ),

                  // 1. Pitch Area (Word Document Sheet Column: 80 chars/line, 1.65 line-height)
                  Padding(
                    padding: EdgeInsets.fromLTRB(docPadX, 12, docPadX, 24),
                    child: Tooltip(
                      key: const ValueKey('spark_pitch_tooltip'),
                      message: topTooltipMessage,
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if ((event is KeyDownEvent ||
                                  event is KeyRepeatEvent) &&
                              (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.numpadEnter) &&
                              (HardwareKeyboard.instance.isMetaPressed ||
                                  HardwareKeyboard.instance.isControlPressed)) {
                            generateConceptBlueprint();
                            return KeyEventResult.handled;
                          }
                          return _handleMultilinePitchKeyEvent(
                            event,
                            _sparkController,
                            onSubmit: refinePitchInPlace,
                          );
                        },
                        child: TextField(
                          key: const ValueKey('spark_input_field'),
                          controller: _sparkController,
                          focusNode: _sparkFocusNode,
                          minLines: 5,
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
                            hintMaxLines: 4,
                            hintText:
                                'Input your game idea (e.g., A cozy submarine roguelike where you salvage sunken megastructures and brew coffee for your deep-sea crew between dives)...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: pitchFontSize,
                              height: 1.65,
                              color: textMuted,
                            ),
                            isCollapsed: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 2. Inline Refine Bar with Larger Return Icon (↵, 20px), Shift+Enter & 80-Char Word Wrap
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: docPadX,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: bgRecessed,
                      border: Border(top: BorderSide(color: borderSubtle)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Tooltip(
                            key: const ValueKey('spark_refine_tooltip'),
                            message: refineTooltipMessage,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: bgBase,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: borderSubtle),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Focus(
                                      onKeyEvent: (node, event) =>
                                          _handleMultilinePitchKeyEvent(
                                        event,
                                        _sparkTweakController,
                                        onSubmit: refinePitchInPlace,
                                      ),
                                      child: TextField(
                                        key: const ValueKey(
                                          'spark_tweak_input_field',
                                        ),
                                        controller: _sparkTweakController,
                                        focusNode: _sparkTweakFocusNode,
                                        minLines: 1,
                                        maxLines: null,
                                        keyboardType: TextInputType.multiline,
                                        textInputAction:
                                            TextInputAction.newline,
                                        inputFormatters: const [
                                          MaxColumnLineWrapFormatter(
                                            maxCharsPerLine:
                                                _kSparkMaxCharsPerLine,
                                          ),
                                        ],
                                        onChanged: (_) => _rebuild(),
                                        style: GoogleFonts.inter(
                                          fontSize: refineFontSize,
                                          height: 1.48,
                                          color: textPrimary,
                                        ),
                                        decoration: InputDecoration(
                                          hintMaxLines: 1,
                                          hintText: refineHintText,
                                          hintStyle: GoogleFonts.inter(
                                            fontSize: refineFontSize,
                                            height: 1.48,
                                            color: textMuted,
                                          ),
                                          isCollapsed: true,
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                        ),
                                        onSubmitted: (_) =>
                                            refinePitchInPlace(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: hasPitchContent
                                        ? 'Submit refinement (Return)'
                                        : 'Input your game idea above first',
                                    child: InkWell(
                                      key: const ValueKey(
                                        'ingest_idea_summary_btn',
                                      ),
                                      onTap: (!isBusy &&
                                              (hasPitchContent ||
                                                  hasTweakContent))
                                          ? refinePitchInPlace
                                          : null,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        child: Text(
                                          '↵',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            height: 1.0,
                                            color: (hasPitchContent ||
                                                    hasTweakContent)
                                                ? (hasTweakContent
                                                    ? textPrimary
                                                    : textSecondary)
                                                : textMuted.withValues(
                                                    alpha: 0.4,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_sparkUndoStack.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          OutlinedButton(
                            key: const ValueKey('spark_undo_btn'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textSecondary,
                              side: BorderSide(color: borderSubtle),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            onPressed: isBusy ? null : revertUndo,
                            child: Text(
                              'Undo',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── 3. Separated Primary Stage-Gate CTA (Outside & Below the Composer Card) ──
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  key: const ValueKey('direct_generate_blueprint_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: textPrimary,
                    foregroundColor: bgBase,
                    disabledBackgroundColor:
                        textMuted.withValues(alpha: 0.22),
                    disabledForegroundColor:
                        textMuted.withValues(alpha: 0.55),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  onPressed:
                      (!isBusy && (hasPitchContent || hasTweakContent))
                          ? generateConceptBlueprint
                          : null,
                  child: Text(
                    isBusy
                        ? 'Generating 01–08...'
                        : 'Generate Concept Blueprint →',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
