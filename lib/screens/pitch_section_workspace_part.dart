part of 'project_pitch_screen.dart';

extension _PitchSectionWorkspaceExt on _ProjectPitchScreenState {
  Color get _secT1Primary => isDark ? const Color(0xFFF9FAFB) : textPrimary;
  Color get _secT2Body => isDark ? const Color(0xFFD1D5DB) : textSecondary;
  Color get _secT3Label => isDark ? const Color(0xFF8E95A5) : textMuted;
  Color get _secT4Muted => isDark ? const Color(0xFF636A78) : textMuted;
  Color get _secHairline =>
      isDark ? Colors.white.withValues(alpha: 0.065) : borderSubtle;

  // ── Inline Click-to-Edit Box (Replaces Popup AlertDialogs Across Stage 1) ──
  Widget _buildInlineEditorBox({
    required String editKey,
    required ValueChanged<String> onSave,
    String hintText = 'Edit text...',
  }) {
    void commitSave() {
      final trimmed = _inlineItemEditController.text.trim();
      _rebuild(() {
        _activeInlineEditKey = null;
      });
      if (trimmed.isNotEmpty) {
        onSave(trimmed);
      }
    }

    void cancelEdit() {
      _rebuild(() {
        _activeInlineEditKey = null;
      });
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _secT1Primary.withValues(alpha: 0.65),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  cancelEdit();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                key: ValueKey('stage1_inline_edit_field_$editKey'),
                controller: _inlineItemEditController,
                autofocus: true,
                maxLines: 2,
                minLines: 1,
                style: GoogleFonts.inter(fontSize: 15, color: _secT1Primary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hintText,
                  hintStyle: GoogleFonts.inter(fontSize: 14, color: _secT4Muted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                ),
                onSubmitted: (_) => commitSave(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            key: ValueKey('stage1_inline_save_btn_$editKey'),
            onTap: commitSave,
            borderRadius: BorderRadius.circular(5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _secT1Primary,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '✓ Save',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: bgBase,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            key: ValueKey('stage1_inline_cancel_btn_$editKey'),
            onTap: cancelEdit,
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '×',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _secT3Label,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticky Bottom AI Co-Designer Bar (Centered 920px Single Column) ────────
  Widget _buildConceptStickyBottomDock(ProjectConceptBlueprint draft) {
    final focusedIdx = _focusedBentoSectionIdx;
    final focusedSec =
        (focusedIdx != null && focusedIdx >= 0 && focusedIdx < _sections.length)
            ? _sections[focusedIdx]
            : null;

    Future<void> submitDockChat() async {
      final text = _agentPromptController.text.trim();
      if (text.isEmpty || widget.workbench.isAgentBusy) return;
      if (focusedSec != null && focusedIdx != null) {
        await _submitSectionPrompt(
          draft,
          focusedIdx,
          controller: _agentPromptController,
        );
      } else {
        _agentPromptController.clear();
        await widget.workbench.sendConceptChatMessage(text);
      }
    }

    return Container(
      key: const ValueKey('concept_sticky_bottom_dock'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: bgRecessed,
        border: Border(top: BorderSide(color: borderSubtle)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _measureColumnMaxWidth),
          child: Row(
            children: [
              // Active Scope Badge (All 01–09 or Focused Section)
              InkWell(
                key: const ValueKey('bento_dock_scope_badge'),
                onTap: focusedSec == null
                    ? null
                    : () => _rebuild(() => _focusedBentoSectionIdx = null),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: focusedSec != null ? _secT1Primary : bgSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: focusedSec != null ? _secT1Primary : borderSubtle,
                    ),
                  ),
                  child: Text(
                    focusedSec != null
                        ? '${focusedSec.numLabel} ${focusedSec.shortTitle} ×'
                        : '✦ AI CO-DESIGNER',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: focusedSec != null ? bgBase : _secT3Label,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: bgBase,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderBright),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('full_blueprint_global_chat_input'),
                          controller: _agentPromptController,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: _secT1Primary,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: focusedSec != null
                                ? 'Ask AI to refine ${focusedSec.numLabel} ${focusedSec.shortTitle}...'
                                : 'Ask AI to refine any section (e.g. "Add 2 more core loop beats" or "Switch engine to Unity")...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 13.5,
                              color: _secT4Muted,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onSubmitted: (_) => submitDockChat(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        key: const ValueKey('full_blueprint_global_chat_send_btn'),
                        onTap:
                            widget.workbench.isAgentBusy ? null : submitDockChat,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.workbench.isAgentBusy
                                ? '...'
                                : 'Update Blueprint',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tailored Single-Column Section Content (01..08) ────────────────────────
  Widget _buildSectionContentWidget(
    ProjectConceptBlueprint draft,
    int sectionIdx, {
    bool isReadOnlySummary = false,
  }) {
    switch (sectionIdx) {
      case 0: // 01 Goal — Lead Sentence + Aligned 2-Column Verb Clauses
        return _buildStructuredGoalSection(
          draft,
          onEditTap: isReadOnlySummary
              ? null
              : () => _startInlineEdit(
                    'goal',
                    ProjectConceptBlueprint.sanitizeGoalText(draft.goal),
                  ),
        );
      case 1: // 02 Game Spec — 4-Across Open Spec Strip
        return _buildKvSpecGrid(
          isGameSpec: true,
          keys: const ['CAMERA VIEW', 'CONTROLS', 'PLAYER MODE', 'ARENA STRUCTURE'],
          values: draft.gameSpec,
        );
      case 2: // 03 Tech Spec — 4-Across Open Spec Strip
        return _buildKvSpecGrid(
          isGameSpec: false,
          keys: const ['ENGINE', 'PLATFORM', 'ASSET PIPELINE', 'NETWORK / SAVE'],
          values: draft.techSpec,
        );
      case 3: // 04 Design Pillars — 2-Column Split (Bold Left Title | Right Description)
        return _buildDesignPillarCards(draft, isReadOnlySummary: isReadOnlySummary);
      case 4: // 05 Trade-Offs — Aligned 3-Column Comparison (Priority X | OVER | Priority Y)
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
          onAddSave: isReadOnlySummary
              ? null
              : (val) => widget.workbench.updateConceptDraft((d) {
                    d.tradeOffs = [...d.tradeOffs, val];
                  }),
        );
      case 5: // 06 Core Loop — Aligned E01..E0N Open Beat Rows
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
          onAddSave: isReadOnlySummary
              ? null
              : (val) => widget.workbench.updateConceptDraft((d) {
                    d.coreLoopBeats = [...d.coreLoopBeats, val];
                  }),
        );
      case 6: // 07 Out of Scope — 2-Column Grid of Open Exclusions
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
          onAddSave: isReadOnlySummary
              ? null
              : (val) => widget.workbench.updateConceptDraft((d) {
                    d.exclusions = [...d.exclusions, val];
                  }),
        );
      case 7: // 08 Done When — Open Playtest Gate Statement
      default:
        return _buildCalloutStatement(
          draft.doneWhen,
          highlightMetrics: true,
          onEditTap: () => _startInlineEdit('done_when', draft.doneWhen),
        );
    }
  }

  // ── 01 Goal: Lead Sentence + Aligned 2-Column Verb Clauses (Zero Inner Box) ─
  Widget _buildStructuredGoalSection(
    ProjectConceptBlueprint draft, {
    VoidCallback? onEditTap,
  }) {
    if (_activeInlineEditKey == 'goal') {
      return _buildInlineEditorBox(
        editKey: 'goal',
        onSave: (val) => widget.workbench.updateConceptDraft(
          (d) => d.goal = ProjectConceptBlueprint.sanitizeGoalText(val),
        ),
      );
    }
    final sanitized = ProjectConceptBlueprint.sanitizeGoalText(draft.goal);
    final colonIdx = sanitized.indexOf(':');
    String headline = sanitized;

    if (colonIdx > 0 && colonIdx <= 48 && colonIdx < sanitized.length - 1) {
      headline = sanitized.substring(colonIdx + 1).trim();
    }

    final clauses = _extractGoalClauses(headline, draft.coreLoopBeats);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('stage1_goal_structured_card'),
        onTap: onEditTap,
        borderRadius: BorderRadius.circular(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              headline,
              style: GoogleFonts.inter(
                fontSize: _measureLeadFontSize,
                fontWeight: FontWeight.w700,
                height: 1.48,
                color: _secT1Primary,
              ),
            ),
            if (clauses.isNotEmpty) ...[
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < clauses.length; i++)
                    Container(
                      key: ValueKey('stage1_goal_clause_card_$i'),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: _secHairline),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          SizedBox(
                            width: _isMobileMeasure ? 100 : 132,
                            child: Text(
                              clauses[i].title.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: _secT3Label,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              clauses[i].body,
                              style: GoogleFonts.inter(
                                fontSize: _measureBodyFontSize,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                                color: _secT2Body,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<({String title, String body})> _extractGoalClauses(
    String headline,
    List<String> coreLoopBeats,
  ) {
    final lower = headline.toLowerCase();
    final whereIdx = lower.indexOf('where you ');
    if (whereIdx != -1) {
      final afterWhere =
          headline.substring(whereIdx + 'where you '.length).trim();
      final parts = afterWhere
          .split(_goalClauseSplitRegex)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length >= 3) {
        return List.generate(3, (i) {
          final rawClause = parts[i];
          final formattedClause =
              rawClause[0].toUpperCase() + rawClause.substring(1);
          final body = formattedClause.endsWith('.')
              ? formattedClause
              : '$formattedClause.';
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
    if (lower.contains('sell') ||
        lower.contains('ammo') ||
        lower.contains('load')) {
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

  // ── 08 Done When: Open Playtest Gate Statement (Zero Nested Callout Box) ───
  Widget _buildCalloutStatement(
    String statement, {
    required bool highlightMetrics,
    VoidCallback? onEditTap,
  }) {
    if (_activeInlineEditKey == 'done_when') {
      return _buildInlineEditorBox(
        editKey: 'done_when',
        onSave: (val) =>
            widget.workbench.updateConceptDraft((d) => d.doneWhen = val),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEditTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            statement,
            style: GoogleFonts.inter(
              fontSize: _measureBodyFontSize + 1.5,
              fontWeight: FontWeight.w600,
              height: 1.52,
              color: _secT1Primary,
            ),
          ),
        ),
      ),
    );
  }

  // ── 02 Game Spec & 03 Tech Spec: 4-Across Open Spec Strip (Zero Tile Boxes) ─
  Widget _buildKvSpecGrid({
    required bool isGameSpec,
    required List<String> keys,
    required List<String> values,
  }) {
    final pairs = List.generate(keys.length, (i) {
      final val = i < values.length ? values[i] : '—';
      return MapEntry(keys[i], val);
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        // 2x2 grid on narrow screens (< 580px)
        if (constraints.maxWidth < 580) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildKvCell(
                      isGameSpec: isGameSpec,
                      cellIndex: 0,
                      k: pairs[0].key,
                      v: pairs[0].value,
                      showRightDivider: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildKvCell(
                      isGameSpec: isGameSpec,
                      cellIndex: 1,
                      k: pairs[1].key,
                      v: pairs[1].value,
                      showRightDivider: false,
                    ),
                  ),
                ],
              ),
              Divider(height: 22, thickness: 1, color: _secHairline),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildKvCell(
                      isGameSpec: isGameSpec,
                      cellIndex: 2,
                      k: pairs[2].key,
                      v: pairs[2].value,
                      showRightDivider: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildKvCell(
                      isGameSpec: isGameSpec,
                      cellIndex: 3,
                      k: pairs[3].key,
                      v: pairs[3].value,
                      showRightDivider: false,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        // 4-across open spec strip on desktop/tablet (>= 580px)
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 18),
                Expanded(
                  child: _buildKvCell(
                    isGameSpec: isGameSpec,
                    cellIndex: i,
                    k: pairs[i].key,
                    v: pairs[i].value,
                    showRightDivider: i < 3,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildKvCell({
    required bool isGameSpec,
    required int cellIndex,
    required String k,
    required String v,
    required bool showRightDivider,
  }) {
    final editKey = 'kv_${isGameSpec ? "game" : "tech"}_$cellIndex';
    if (_activeInlineEditKey == editKey) {
      return _buildInlineEditorBox(
        editKey: editKey,
        onSave: (val) => _applyDirectKvValue(
          isGameSpec: isGameSpec,
          cellIndex: cellIndex,
          newValue: val,
        ),
      );
    }

    final presets = _kvPresetsForCell(isGameSpec, cellIndex);
    return Material(
      color: Colors.transparent,
      child: PopupMenuButton<String>(
        key: ValueKey(
          'kv_cell_dropdown_${isGameSpec ? "game" : "tech"}_$cellIndex',
        ),
        tooltip: 'Click to pick $k preset or type custom value',
        color: bgSurface,
        onSelected: (val) {
          if (val == '__custom__') {
            _startInlineEdit(editKey, v);
          } else {
            _applyDirectKvValue(
              isGameSpec: isGameSpec,
              cellIndex: cellIndex,
              newValue: val,
            );
          }
        },
        itemBuilder: (ctx) => [
          for (final p in presets)
            PopupMenuItem<String>(
              value: p,
              child: Text(
                p,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: p == v ? FontWeight.w700 : FontWeight.w500,
                  color: p == v ? _secT1Primary : _secT2Body,
                ),
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: '__custom__',
            child: Text(
              '✎ Custom Edit...',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _secT1Primary,
              ),
            ),
          ),
        ],
        child: Container(
          padding: EdgeInsets.only(
            right: showRightDivider ? 14 : 0,
            top: 2,
            bottom: 2,
          ),
          decoration: BoxDecoration(
            border: showRightDivider
                ? Border(right: BorderSide(color: _secHairline))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      k,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: _secT3Label,
                      ),
                    ),
                  ),
                  Text(
                    '▾',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _secT4Muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                v.trim().isEmpty ? 'Click to set...' : v,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: _measureSpecValueSize,
                  height: 1.3,
                  fontWeight:
                      v.trim().isEmpty ? FontWeight.w500 : FontWeight.w700,
                  fontStyle:
                      v.trim().isEmpty ? FontStyle.italic : FontStyle.normal,
                  color: v.trim().isEmpty ? _secT4Muted : _secT1Primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Splits `"Lead-In Label: Description text"` so the lead-in before `:` is bold & bright
  /// and the description after `:` is slightly softer for instant greyscale scanability.
  Widget _buildFormattedLeadInText(String rawText) {
    final colonIdx = rawText.indexOf(':');
    if (colonIdx <= 0 || colonIdx >= rawText.length - 1) {
      return Text(
        rawText,
        style: GoogleFonts.inter(
          fontSize: _measureBodyFontSize,
          fontWeight: FontWeight.w500,
          height: 1.5,
          color: _secT1Primary,
        ),
      );
    }

    final leadIn = rawText.substring(0, colonIdx);
    final rest = rawText.substring(colonIdx + 1).trim();

    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: _measureBodyFontSize,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text: '$leadIn — ',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: _secT1Primary,
            ),
          ),
          TextSpan(
            text: rest,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: _secT2Body,
            ),
          ),
        ],
      ),
    );
  }

  // ── 04 Design Pillars: Stacked inside 75ch/65ch/50ch Measure ────────────────
  Widget _buildDesignPillarCards(
    ProjectConceptBlueprint draft, {
    bool isReadOnlySummary = false,
  }) {
    final pillars = draft.designPillars;

    Widget buildPillarRow(int idx) {
      final editKey = 'pillar_$idx';
      final raw = pillars[idx];
      final parsedPillar =
          ProjectConceptBlueprint.parsePillarTitleAndBody(raw, idx);
      final String title = parsedPillar.title;
      final String body = parsedPillar.body;

      if (_activeInlineEditKey == editKey) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _buildInlineEditorBox(
            editKey: editKey,
            onSave: (val) => widget.workbench.updateConceptDraft((d) {
              final next = List<String>.from(d.designPillars);
              next[idx] = ProjectConceptBlueprint.ensureNamedPillar(val, idx);
              d.designPillars = next;
            }),
          ),
        );
      }

      return Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('stage1_pillar_row_$idx'),
          onTap: () => _startInlineEdit(
            editKey,
            '${parsedPillar.title}: ${parsedPillar.body}',
          ),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: EdgeInsets.only(
              top: idx == 0 ? 2 : 12,
              bottom: idx == pillars.length - 1 ? 2 : 12,
            ),
            decoration: BoxDecoration(
              border: idx < pillars.length - 1
                  ? Border(bottom: BorderSide(color: _secHairline))
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: _measureBodyFontSize + 0.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: _secT1Primary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: GoogleFonts.inter(
                          fontSize: _measureBodyFontSize,
                          height: 1.52,
                          color: _secT2Body,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isReadOnlySummary && pillars.length > 1) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => widget.workbench.updateConceptDraft((d) {
                      final next = List<String>.from(d.designPillars)
                        ..removeAt(idx);
                      d.designPillars = next;
                    }),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      child: Text(
                        '×',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _secT4Muted,
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
        if (!isReadOnlySummary && _activeInlineEditKey == 'add_pillar') ...[
          const SizedBox(height: 10),
          _buildInlineEditorBox(
            editKey: 'add_pillar',
            hintText:
                'Type a new Design Pillar (e.g. Every Choice Echoes: Visible arena feedback)...',
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
        ],
      ],
    );
  }

  // ── 06 Core Loop: Open E01..E0N Rows Separated by Hairlines ────────────────
  Widget _buildIndexedRows({
    required String prefix,
    required List<String> items,
    required bool isCoreLoop,
    void Function(int index, String newValue)? onEditItem,
    void Function(int oldIndex, int newIndex)? onReorderItem,
    void Function(int index)? onDeleteItem,
    ValueChanged<String>? onAddSave,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (_activeInlineEditKey == 'indexed_${prefix.toLowerCase()}_$i' &&
              onEditItem != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _buildInlineEditorBox(
                editKey: 'indexed_${prefix.toLowerCase()}_$i',
                onSave: (val) => onEditItem(i, val),
              ),
            )
          else
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('stage1_indexed_row_${prefix.toLowerCase()}_$i'),
                onTap: onEditItem == null
                    ? null
                    : () => _startInlineEdit(
                          'indexed_${prefix.toLowerCase()}_$i',
                          items[i],
                        ),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: EdgeInsets.only(
                    top: i == 0 ? 2 : 12,
                    bottom: i == items.length - 1 ? 2 : 12,
                  ),
                  decoration: BoxDecoration(
                    border: i < items.length - 1
                        ? Border(bottom: BorderSide(color: _secHairline))
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(
                          isCoreLoop
                              ? 'E${(i + 1).toString().padLeft(2, '0')}'
                              : '$prefix·${(i + 1).toString().padLeft(2, '0')}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _secT3Label,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            child: Text(
                              '↑',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: i > 0
                                    ? _secT3Label
                                    : _secT4Muted.withValues(alpha: 0.35),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            child: Text(
                              '↓',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: i < items.length - 1
                                    ? _secT3Label
                                    : _secT4Muted.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (onDeleteItem != null) ...[
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => onDeleteItem(i),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            child: Text(
                              '×',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _secT4Muted,
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
        if (onAddSave != null && _activeInlineEditKey == 'add_beat') ...[
          const SizedBox(height: 10),
          _buildInlineEditorBox(
            editKey: 'add_beat',
            hintText:
                'Type a Core Loop Beat (e.g. Extract & Upgrade: Spend gathered ore)...',
            onSave: onAddSave,
          ),
        ],
      ],
    );
  }

  // ── 05 Trade-Offs: Aligned 3-Column Comparison (Priority X | OVER | Priority Y) ─
  Widget _buildTradeOffSplitBars(
    List<String> tradeOffs, {
    void Function(int index, String newValue)? onEditItem,
    void Function(int index)? onDeleteItem,
    ValueChanged<String>? onAddSave,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < tradeOffs.length; i++) ...[
          if (_activeInlineEditKey == 'tradeoff_$i' && onEditItem != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _buildInlineEditorBox(
                editKey: 'tradeoff_$i',
                onSave: (val) => onEditItem(i, val),
              ),
            )
          else
            _buildSingleTradeOffBar(
              tradeOffs[i],
              isFirst: i == 0,
              isLast: i == tradeOffs.length - 1,
              onTap: onEditItem == null
                  ? null
                  : () => _startInlineEdit('tradeoff_$i', tradeOffs[i]),
              onDelete: onDeleteItem == null ? null : () => onDeleteItem(i),
            ),
        ],
        if (onAddSave != null && _activeInlineEditKey == 'add_tradeoff') ...[
          const SizedBox(height: 10),
          _buildInlineEditorBox(
            editKey: 'add_tradeoff',
            hintText:
                'Type X over Y trade-off (e.g. Immediate arcade feel over simulation depth)...',
            onSave: onAddSave,
          ),
        ],
      ],
    );
  }

  Widget _buildSingleTradeOffBar(
    String rawRule, {
    required bool isFirst,
    required bool isLast,
    VoidCallback? onTap,
    VoidCallback? onDelete,
  }) {
    final clean = rawRule.replaceFirst(_prioritizePrefixRegex, '');
    final parts = clean.split(_overSplitRegex);
    final winText = parts.isNotEmpty ? parts[0].trim() : clean;
    final loseText = parts.length > 1
        ? parts.sublist(1).join(' over ').trim()
        : 'secondary complexity';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: EdgeInsets.only(
            top: isFirst ? 2 : 12,
            bottom: isLast ? 2 : 12,
          ),
          decoration: BoxDecoration(
            border: !isLast
                ? Border(bottom: BorderSide(color: _secHairline))
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  winText,
                  style: GoogleFonts.inter(
                    fontSize: _measureBodyFontSize,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    color: _secT1Primary,
                  ),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  'OVER',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: _secT4Muted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  loseText,
                  style: GoogleFonts.inter(
                    fontSize: _measureBodyFontSize - 0.5,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                    color: _secT4Muted,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: _secT4Muted.withValues(alpha: 0.75),
                  ),
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    child: Text(
                      '×',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _secT4Muted,
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

  // ── 07 Out of Scope: 2-Column Grid of Open Exclusions (Zero Chip Boxes) ────
  Widget _buildCutGuardrailChips(
    List<String> exclusions, {
    void Function(int index, String newValue)? onEditItem,
    void Function(int index)? onDeleteItem,
    ValueChanged<String>? onAddSave,
  }) {
    Widget buildExclusionRow(int idx, {required bool showBottomHairline}) {
      final editKey = 'exclusion_$idx';
      if (_activeInlineEditKey == editKey && onEditItem != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _buildInlineEditorBox(
            editKey: editKey,
            onSave: (val) => onEditItem(idx, val),
          ),
        );
      }
      return Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('stage1_exclusion_row_$idx'),
          onTap: onEditItem == null
              ? null
              : () => _startInlineEdit(editKey, exclusions[idx]),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: showBottomHairline
                  ? Border(bottom: BorderSide(color: _secHairline))
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '—',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _secT4Muted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    exclusions[idx],
                    style: GoogleFonts.inter(
                      fontSize: _measureBodyFontSize,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                      color: _secT2Body,
                    ),
                  ),
                ),
                if (onDeleteItem != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => onDeleteItem(idx),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      child: Text(
                        '×',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _secT4Muted,
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
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 560 || exclusions.length <= 1) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < exclusions.length; i++)
                    buildExclusionRow(
                      i,
                      showBottomHairline: i < exclusions.length - 1,
                    ),
                ],
              );
            }

            final rows = <Widget>[];
            for (int i = 0; i < exclusions.length; i += 2) {
              final hasRight = i + 1 < exclusions.length;
              final isLastPair = i + 2 >= exclusions.length;
              rows.add(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: buildExclusionRow(
                        i,
                        showBottomHairline: !isLastPair,
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      child: hasRight
                          ? buildExclusionRow(
                              i + 1,
                              showBottomHairline: !isLastPair,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            );
          },
        ),
        if (onAddSave != null && _activeInlineEditKey == 'add_exclusion') ...[
          const SizedBox(height: 10),
          _buildInlineEditorBox(
            editKey: 'add_exclusion',
            hintText:
                'Type an Out of Scope exclusion (e.g. No multiplayer networking in v0.1)...',
            onSave: onAddSave,
          ),
        ],
      ],
    );
  }
}
