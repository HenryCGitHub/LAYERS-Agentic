part of 'project_pitch_screen.dart';

extension _PitchSparkAndOutlinerExt on _ProjectPitchScreenState {
  // ── Initial New Project Idea Intake & Expansion Launcher (Before Concept Draft Exists) ──
  Widget _buildInitialSparkLauncher() {
    final intake = widget.workbench.sparkIntake;
    final expansionCards = intake?.expansionCards ?? const [];

    Future<void> submitIdeaToAgent() async {
      final text = _sparkController.text
          .replaceAll(RegExp(r'\s*\n\s*'), ' ')
          .trim();
      if (text.isEmpty && intake == null) return;
      _sparkController.clear();
      await widget.workbench.ingestOrRefineSparkIdea(text);
    }

    Widget buildExpansionPlayingCard(int index) {
      final card = expansionCards[index];
      final isSelected = card.isSelected;

      return Material(
        color: isSelected ? bgHover.withValues(alpha: 0.45) : Colors.transparent,
        child: InkWell(
          key: ValueKey('spark_card_$index'),
          onTap: widget.workbench.isAgentBusy
              ? null
              : () => widget.workbench.toggleSparkExpansionCard(index),
          child: Container(
            padding: EdgeInsets.fromLTRB(isSelected ? 13 : 8, 13, 8, 13),
            decoration: BoxDecoration(
              border: Border(
                left: isSelected
                    ? BorderSide(color: accentEmerald, width: 3)
                    : BorderSide.none,
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 16,
                    color: isSelected ? accentEmerald : textMuted,
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                card.title,
                                style: AppTheme.displayFont(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                card.badge,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            isSelected
                                ? '✓ Added to Concept'
                                : '+ Add to Concept',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color:
                                  isSelected ? accentEmerald : textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        card.description,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          height: 1.48,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderSubtle)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'STEP 1A · NEW PROJECT',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: accentCyan,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pitch your game idea to the Agent & shape your Concept Summary',
                style: AppTheme.displayFont(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                intake == null
                    ? 'Tell the Agent your game idea below so it can summarize the core loop back to you and generate tailored Concept Addition Cards.'
                    : 'Review the Agent\'s ingested summary below. Use the same input field to ask for changes, or toggle the Concept Addition rows on/off before clicking Start Concept Blueprint →.',
                style: GoogleFonts.inter(fontSize: 13, color: textSecondary),
              ),
            ],
          ),
        ),
        if (intake != null) ...[
          const SizedBox(height: 16),
          Container(
            key: const ValueKey('agent_idea_summary_card'),
            padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6, right: 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: accentEmerald,
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentEmerald,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'AGENT IDEA SUMMARY',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: accentEmerald,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          intake.workingTitle,
                          style: AppTheme.displayFont(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          key: const ValueKey('fast_track_concept_review_btn'),
                          onTap: widget.workbench.isAgentBusy
                              ? null
                              : () => widget.workbench.startConceptInterview(
                                    _sparkController.text,
                                    true,
                                  ),
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accentEmerald.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: accentEmerald.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              'Fast-Track to Review ◫',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: accentEmerald,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          key: const ValueKey('clear_idea_summary_btn'),
                          onTap: () => widget.workbench.clearSparkIdeaIntake(),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              'Reset ×',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: textMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  intake.effectiveSummary,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.52,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    for (final m in intake.mechanics)
                      Text(
                        '⚡ $m',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: textSecondary,
                        ),
                      ),
                    for (final added
                        in intake.expansionCards.where((c) => c.isSelected))
                      Text(
                        '✓ + ${added.title}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accentEmerald,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Focus(
                      onKeyEvent: (node, event) =>
                          _handleMultilinePitchKeyEvent(
                        event,
                        _sparkController,
                        onSubmit: submitIdeaToAgent,
                      ),
                      child: TextField(
                        key: const ValueKey('spark_input_field'),
                        controller: _sparkController,
                        focusNode: _sparkFocusNode,
                        minLines: 1,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        inputFormatters: const [
                          MaxColumnLineWrapFormatter(maxCharsPerLine: 70),
                        ],
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintMaxLines: 1,
                          hintText: intake == null
                              ? 'Pitch your game idea (70 chars/line · Shift+Enter for new line)...'
                              : 'Tell the Agent what to change or add (Shift+Enter for new line)...',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 13,
                            color: textMuted,
                          ),
                          filled: true,
                          fillColor: bgRecessed,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: borderSubtle),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                BorderSide(color: borderBright, width: 1.5),
                          ),
                        ),
                        onSubmitted: (_) => submitIdeaToAgent(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                key: const ValueKey('ingest_idea_summary_btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: textPrimary,
                  backgroundColor: bgRecessed,
                  side: BorderSide(color: borderBright),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed:
                    widget.workbench.isAgentBusy ? null : submitIdeaToAgent,
                child: Text(
                  intake == null ? 'Summarize Idea' : 'Update Summary',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('import_existing_gdd_btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: textPrimary,
                  backgroundColor: bgRecessed,
                  side: BorderSide(color: borderBright),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: widget.workbench.isAgentBusy
                    ? null
                    : () => _showImportGddDialog(context),
                icon: Icon(Icons.description_outlined, size: 14, color: textSecondary),
                label: Text(
                  'Import GDD / Notes',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (intake != null) ...[
                const SizedBox(width: 10),
                ElevatedButton(
                  key: const ValueKey('start_concept_interview_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: focalAccent,
                    foregroundColor: focalAccentFg,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    elevation: 0,
                  ),
                  onPressed: widget.workbench.isAgentBusy
                      ? null
                      : () => widget.workbench.startConceptInterview(
                            _sparkController.text
                                .replaceAll(RegExp(r'\s*\n\s*'), ' ')
                                .trim(),
                          ),
                  child: Text(
                    widget.workbench.isAgentBusy
                        ? 'Drafting Blueprint...'
                        : 'Start Concept Blueprint →',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (intake != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderSubtle)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'IDEAS TO ADD TO YOUR CONCEPT (CLICK TO TOGGLE ON / OFF)',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: textSecondary,
                    ),
                  ),
                  InkWell(
                    key: const ValueKey('shuffle_spark_ideas_btn'),
                    onTap: () => widget.workbench.shuffleSparkExpansionCards(),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        '↻ Refresh Suggestions',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: accentCyan,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < expansionCards.length; i++)
                  buildExpansionPlayingCard(i),
              ],
            ),
          ],
          if (widget.workbench.savedProjects.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              key: const ValueKey('stage1_saved_projects_strip'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bgRecessed,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SAVED PROJECTS IN VAULT (${widget.workbench.savedProjects.length}) — 1-CLICK RESUME',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: textSecondary,
                        ),
                      ),
                      Text(
                        widget.workbench.isCloudSynced ? '☁ Cloud Synced' : '⚡ Local Auto-Save',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in widget.workbench.savedProjects)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: bgSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                key: ValueKey('spark_resume_project_${p.id}'),
                                onTap: () => widget.workbench.switchProject(p.id),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.folder_open_rounded,
                                      size: 13,
                                      color: textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      p.title,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Resume →',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: accentEmerald,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                key: ValueKey('spark_duplicate_project_${p.id}'),
                                onTap: () => widget.workbench.duplicateProject(p.id),
                                child: Tooltip(
                                  message: 'Duplicate Project',
                                  child: Icon(
                                    Icons.copy_all_rounded,
                                    size: 13,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                key: ValueKey('spark_delete_project_${p.id}'),
                                onTap: () => widget.workbench.deleteProject(p.id),
                                child: Tooltip(
                                  message: 'Delete Project',
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 13,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      );
  }

  /// Option 5: Opens a dialog to paste an existing GDD, Notion note, or README document,
  /// extracts all 8 Concept sections, and jumps straight to `Step 09 · Full Concept Review`.
  void _showImportGddDialog(BuildContext context) {
    final gddController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          key: const ValueKey('import_gdd_dialog'),
          backgroundColor: bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: borderBright),
          ),
          title: Row(
            children: [
              Icon(Icons.description_outlined, size: 18, color: accentAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Import Existing GDD / Pitch Notes',
                  style: AppTheme.displayFont(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste your unstructured GDD, Notion notes, or README below. The Agent will extract all 8 Concept sections (Goal, Game Spec, Tech Spec, Pillars, Trade-Offs, Core Loop, Out of Scope, Done When) and jump straight to Step 09 · Full Concept Review.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.45,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('import_gdd_text_field'),
                  controller: gddController,
                  maxLines: 9,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    height: 1.45,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        '# Neon Grapple Arena\nGoal: Build a fast 3D grappling hook arena shooter in Godot 4.\nEngine: Godot 4 (3D)\nCore Loop: Grapple -> Shoot -> Bank Score -> Reset\nDone When: Playtester completes 3 consecutive arena waves without clipping.',
                    hintStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      color: textMuted,
                    ),
                    filled: true,
                    fillColor: bgRecessed,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: accentAmber, width: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: textSecondary,
                ),
              ),
            ),
            ElevatedButton.icon(
              key: const ValueKey('confirm_import_gdd_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentEmerald,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: () async {
                final raw = gddController.text.trim();
                if (raw.isEmpty) return;
                Navigator.of(ctx).pop();
                await widget.workbench.importExistingGddAndJumpToReview(raw);
              },
              icon: const Icon(Icons.auto_awesome_rounded, size: 14),
              label: Text(
                'Extract 8-Section Blueprint & Jump to Review →',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Unified 2-Surface Recessed Left Concept Stepper (`01 Goal` ... `09 Releases` + `10 Full Review`) ─
  Widget _buildLeftConceptOutlinerRail(ProjectConceptBlueprint draft) {
    final verifiedCount =
        _visitedSteps.where((idx) => idx >= 0 && idx < _sections.length).length;
    final viewSummary = draft.gameSpec.isNotEmpty ? draft.gameSpec.first : '2D/3D';
    final engineSummary = draft.techSpec.isNotEmpty ? draft.techSpec.first : 'Engine';

    return Container(
      key: const ValueKey('stage1_left_outliner_rail'),
      color: bgRecessed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Flush Top Snapshot Header (Zero 4-sided nested boxes)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        key: const ValueKey('stage1_rename_project_title_btn'),
                        onTap: () => _promptEditProjectTitle(draft),
                        borderRadius: BorderRadius.circular(3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                draft.title.trim().isEmpty
                                    ? 'Concept Blueprint'
                                    : draft.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.edit_outlined,
                              size: 11,
                              color: textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$verifiedCount/${_sections.length} ✓',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: accentEmerald,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$viewSummary · $engineSummary · ${draft.coreLoopBeats.length} Beats',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: textMuted,
                        ),
                      ),
                    ),
                    InkWell(
                      key: const ValueKey('new_spark_reset_btn'),
                      onTap: () => widget.workbench.resetConceptToSpark(),
                      borderRadius: BorderRadius.circular(3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          '+ New Project',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: accentCyan,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Flat 10-Step Section List (`01`..`09` + `10 Full Concept Review` as the last item)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                for (int i = 0; i < _sections.length; i++)
                  _buildOutlineSectionNode(draft, i),
                _buildFinalReviewOutlineNode(verifiedCount: verifiedCount),
              ],
            ),
          ),

          // Quick-Action Footer: Jump straight to 2. Workbench (Build v0.1) from any section
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: InkWell(
              key: const ValueKey('outliner_quick_build_v01_btn'),
              onTap: widget.workbench.isAgentBusy
                  ? null
                  : () => widget.workbench.approveConceptAndBuildRelease(),
              borderRadius: BorderRadius.circular(5),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Text(
                  'Build v0.1 →',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: accentEmerald,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _sectionOutlineMetaBadge(ProjectConceptBlueprint draft, int index) {
    switch (index) {
      case 0:
        return draft.goal.trim().isEmpty ? 'Draft' : 'Locked';
      case 1:
        return draft.gameSpec.isNotEmpty ? draft.gameSpec.first : 'Spec';
      case 2:
        return draft.techSpec.isNotEmpty ? draft.techSpec.first : 'Tech';
      case 3:
        return '${draft.designPillars.length} Pillars';
      case 4:
        return '${draft.tradeOffs.length} Rules';
      case 5:
        return '${draft.coreLoopBeats.length} Beats';
      case 6:
        return '${draft.exclusions.length} Cuts';
      case 7:
        return 'Playtest';
      default:
        return '';
    }
  }

  Widget _buildOutlineSectionNode(ProjectConceptBlueprint draft, int index) {
    final sec = _sections[index];
    final isActive = _currentStep == index;
    final isDone = _visitedSteps.contains(index);
    final metaBadge = _sectionOutlineMetaBadge(draft, index);

    return InkWell(
      key: ValueKey('step_node_$index'),
      onTap: () => _goToStep(index),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 9, 12, 9),
        decoration: BoxDecoration(
          color: isActive
              ? accentCyan.withValues(alpha: 0.09)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isActive ? accentCyan : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                sec.numLabel,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  color: isActive ? accentCyan : textMuted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                sec.shortTitle,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? textPrimary
                      : (isDone ? textSecondary : textMuted),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Text(
                metaBadge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? textPrimary : textMuted,
                ),
              ),
            ),
            if (isDone) ...[
              const SizedBox(width: 6),
              Text(
                '✓',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: accentEmerald,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFinalReviewOutlineNode({required int verifiedCount}) {
    final isActive = _currentStep == _sections.length;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: borderSubtle),
          bottom: BorderSide(color: borderSubtle),
        ),
      ),
      child: InkWell(
        key: const ValueKey('synthesize_concept_btn'),
        onTap: () => _goToStep(_sections.length),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 11, 12, 11),
          decoration: BoxDecoration(
            color: isActive
                ? accentEmerald.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isActive ? accentEmerald : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '09',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: isActive ? accentEmerald : textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Full Concept Review',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      'Inspect all ${_sections.length} sections ($verifiedCount/${_sections.length})',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'READY →',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accentEmerald,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
