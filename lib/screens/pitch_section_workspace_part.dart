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
                        : '✦ AI Ready',
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
                                : 'Update',
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

  // ── 01 Goal: Clean 1-Sentence Lead Statement (Prose Capped at <= 72ch) ──────
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('stage1_goal_structured_card'),
        onTap: onEditTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            headline,
            style: GoogleFonts.inter(
              fontSize: _measureLeadFontSize,
              fontWeight: FontWeight.w600,
              height: 1.5,
              color: _secT1Primary,
            ),
          ),
        ),
      ),
    );
  }

  // ── Telegraphic & Semi-Telegraphic Display Formatters ──────────────────────
  String _capitalizeFirst(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }

  /// Compresses a verbose Trade-Off rule into Strict Telegraphic Style (2–4 words per side).
  ({String win, String lose}) _formatTelegraphicTradeOff(String rawRule) {
    var clean = rawRule.trim();
    final colonIdx = clean.indexOf(':');
    if (colonIdx > 0 && colonIdx < clean.length - 1) {
      final afterColon = clean.substring(colonIdx + 1).trim();
      if (afterColon.toLowerCase().contains(' over ')) {
        clean = afterColon;
      }
    }
    clean = clean
        .replaceFirst(_prioritizePrefixRegex, '')
        .replaceFirst(_versionSuffixNoiseRegex, '')
        .trim();

    String compressHalf(String half) {
      var s = half
          .replaceFirst(_prioritizePrefixRegex, '')
          .replaceFirst(_versionSuffixNoiseRegex, '')
          .trim();
      if (s.endsWith('.')) s = s.substring(0, s.length - 1).trim();
      final rawWords = s.split(_whitespaceRegex).where((w) => w.isNotEmpty).toList();
      if (rawWords.length > 3) {
        final stripped = s.replaceAll(_tradeOffFillerWordRegex, '').trim();
        final filteredWords =
            stripped.split(_whitespaceRegex).where((w) => w.isNotEmpty).toList();
        if (filteredWords.length >= 2) {
          s = filteredWords.take(4).join(' ');
        } else {
          s = rawWords.take(4).join(' ');
        }
      }
      return _capitalizeFirst(s);
    }

    final parts = clean.split(_overSplitRegex);
    final winText = parts.isNotEmpty ? compressHalf(parts[0]) : compressHalf(clean);
    final loseText = parts.length > 1
        ? compressHalf(parts.sublist(1).join(' over '))
        : 'Secondary complexity';
    return (win: winText, lose: loseText);
  }

  /// Formats an Out of Scope item into Strict Telegraphic Style (concise exclusion phrase).
  String _formatTelegraphicExclusion(String raw) {
    var clean = raw.trim();
    final colonIdx = clean.indexOf(':');
    if (colonIdx > 0 && colonIdx <= 32 && colonIdx < clean.length - 1) {
      clean = clean.substring(colonIdx + 1).trim();
    }
    clean = clean.replaceFirst(_versionSuffixNoiseRegex, '').trim();
    if (_exclusionLeadVerbRegex.hasMatch(clean)) {
      clean = 'No ${clean.replaceFirst(_exclusionLeadVerbRegex, '').replaceAll(' and ', ' or ')}';
    }
    if (clean.endsWith('.')) {
      clean = clean.substring(0, clean.length - 1).trim();
    }
    return _capitalizeFirst(clean);
  }

  /// Formats a 02 Game Spec or 03 Tech Spec cell value into a concise telegraphic tag.
  String _formatTelegraphicSpecValue(String raw) {
    var clean = raw.trim().replaceFirst(_offlineOnlyPrefixRegex, '');
    if (clean == 'Twin-Stick (WASD + Mouse Aim)' ||
        clean == 'Twin-Stick (WASD + Aim)') {
      return 'WASD + Mouse';
    }
    if (clean == 'Single-Screen Wave Arena') {
      return 'Single-Screen Arena';
    }
    return clean;
  }

  // ── 08 Done When: Concise Messaging Verification Sentence ──────────────────
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
            statement.trim(),
            style: GoogleFonts.inter(
              fontSize: _measureBodyFontSize,
              fontWeight: FontWeight.w500,
              height: 1.55,
              color: _secT1Primary,
            ),
          ),
        ),
      ),
    );
  }

  // ── 02 Game Spec & 03 Tech Spec: Balanced 2x2 Spec Grid (Single Typeface) ──
  Widget _buildKvSpecGrid({
    required bool isGameSpec,
    required List<String> keys,
    required List<String> values,
  }) {
    final totalCells = keys.length < 4 ? 4 : keys.length;
    final pairs = List.generate(totalCells, (i) {
      final k = i < keys.length ? keys[i] : '—';
      final val = i < values.length ? values[i] : '—';
      return MapEntry(k, val);
    });

    if (_viewportWidth < 420) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < 4; i++) ...[
            if (i > 0) Divider(height: 18, thickness: 1, color: _secHairline),
            _buildKvCell(
              isGameSpec: isGameSpec,
              cellIndex: i,
              k: pairs[i].key,
              v: pairs[i].value,
              showRightDivider: false,
            ),
          ],
        ],
      );
    }

    // Balanced 2x2 Spec Grid on all standard widths
    return Column(
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
        ),
        Divider(height: 20, thickness: 1, color: _secHairline),
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
        ),
      ],
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
              style: GoogleFonts.inter(
                fontSize: 12.5,
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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      k,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: _secT3Label,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      v.trim().isEmpty
                          ? 'Click to set...'
                          : _formatTelegraphicSpecValue(v),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: _measureSpecValueSize,
                        height: 1.3,
                        fontWeight: v.trim().isEmpty
                            ? FontWeight.w500
                            : FontWeight.w700,
                        fontStyle: v.trim().isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: v.trim().isEmpty ? _secT4Muted : _secT1Primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '▾',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _secT4Muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Splits `"Lead-In Label: Description text"` so the lead-in before `:` is bold & bright
  /// and the description after `:` is semi-telegraphic (stripping leading filler verbs).
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

    final leadIn = rawText.substring(0, colonIdx).trim();
    final rawRest = rawText.substring(colonIdx + 1).trim();
    final rest = _capitalizeFirst(
      rawRest.replaceFirst(_leadInFillerVerbRegex, ''),
    );

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

  // ── 04 Design Pillars: Aligned Indexed Hairline Rows (01..0N) ─────────────
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
      final numBadge = (idx + 1).toString().padLeft(2, '0');

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
              top: idx == 0 ? 2 : 10,
              bottom: idx == pillars.length - 1 ? 2 : 10,
            ),
            decoration: BoxDecoration(
              border: idx < pillars.length - 1
                  ? Border(bottom: BorderSide(color: _secHairline))
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SizedBox(
                    width: 28,
                    child: Text(
                      numBadge,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _secT4Muted,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _buildFormattedLeadInText('$title: $body'),
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
                        horizontal: 4,
                        vertical: 1,
                      ),
                      child: Text(
                        '×',
                        style: GoogleFonts.inter(
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

  // ── 06 Core Loop: Numbered 01..0N Single-Font Rows ─────────────────────────
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
                    top: i == 0 ? 2 : 10,
                    bottom: i == items.length - 1 ? 2 : 10,
                  ),
                  decoration: BoxDecoration(
                    border: i < items.length - 1
                        ? Border(bottom: BorderSide(color: _secHairline))
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SizedBox(
                          width: 28,
                          child: Text(
                            (i + 1).toString().padLeft(2, '0'),
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _secT4Muted,
                            ),
                          ),
                        ),
                      ),
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
                              style: GoogleFonts.inter(
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
                              style: GoogleFonts.inter(
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
                              style: GoogleFonts.inter(
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

  // ── 05 Trade-Offs: Flowing Inline X [OVER] Y Hairline Rows (Zero Stretched Gap) ─
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
              index: i,
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
    required int index,
    required bool isFirst,
    required bool isLast,
    VoidCallback? onTap,
    VoidCallback? onDelete,
  }) {
    final telegraphic = _formatTelegraphicTradeOff(rawRule);
    final numBadge = (index + 1).toString().padLeft(2, '0');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('stage1_tradeoff_row_$index'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: EdgeInsets.only(
            top: isFirst ? 2 : 10,
            bottom: isLast ? 2 : 10,
          ),
          decoration: BoxDecoration(
            border: !isLast
                ? Border(bottom: BorderSide(color: _secHairline))
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 28,
                  child: Text(
                    numBadge,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _secT4Muted,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.inter(
                      fontSize: _measureBodyFontSize,
                      height: 1.5,
                    ),
                    children: [
                      TextSpan(
                        text: telegraphic.win,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _secT1Primary,
                        ),
                      ),
                      TextSpan(
                        text: '  over  ',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: _secT4Muted,
                        ),
                      ),
                      TextSpan(
                        text: telegraphic.lose,
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          color: _secT3Label,
                        ),
                      ),
                    ],
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
                      style: GoogleFonts.inter(
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

  // ── 07 Out of Scope: Aligned Telegraphic Exclusion Rows (— Index) ──────────
  Widget _buildCutGuardrailChips(
    List<String> exclusions, {
    void Function(int index, String newValue)? onEditItem,
    void Function(int index)? onDeleteItem,
    ValueChanged<String>? onAddSave,
  }) {
    Widget buildExclusionRow(int idx) {
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
            padding: EdgeInsets.only(
              top: idx == 0 ? 2 : 10,
              bottom: idx == exclusions.length - 1 ? 2 : 10,
            ),
            decoration: BoxDecoration(
              border: idx < exclusions.length - 1
                  ? Border(bottom: BorderSide(color: _secHairline))
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: SizedBox(
                    width: 28,
                    child: Text(
                      '—',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _secT4Muted,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _formatTelegraphicExclusion(exclusions[idx]),
                    style: GoogleFonts.inter(
                      fontSize: _measureBodyFontSize,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
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
                        style: GoogleFonts.inter(
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
        for (int i = 0; i < exclusions.length; i++) buildExclusionRow(i),
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
