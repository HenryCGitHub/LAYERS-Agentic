part of 'project_pitch_screen.dart';

extension _PitchSectionWorkspaceExt on _ProjectPitchScreenState {
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textPrimary.withValues(alpha: 0.7), width: 1.2),
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
                style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hintText,
                  hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                ),
                onSubmitted: (_) => commitSave(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            key: ValueKey('stage1_inline_save_btn_$editKey'),
            onTap: commitSave,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentEmerald.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: accentEmerald.withValues(alpha: 0.6)),
              ),
              child: Text(
                '✓ Save',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accentEmerald,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            key: ValueKey('stage1_inline_cancel_btn_$editKey'),
            onTap: cancelEdit,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '×',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
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

  // ── Non-Jumping Scoped Bottom Co-Design Dock (3×3 Bento Board) ─────────────
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: bgRecessed,
        border: Border(top: BorderSide(color: borderSubtle)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1580),
          child: Row(
            children: [
              // Active Scope Badge (All 01–09 or Focused Bento Section)
              InkWell(
                key: const ValueKey('bento_dock_scope_badge'),
                onTap: focusedSec == null
                    ? null
                    : () => _rebuild(() => _focusedBentoSectionIdx = null),
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: focusedSec != null ? focalAccent : bgSurface,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: focusedSec != null ? focalAccent : borderSubtle,
                    ),
                  ),
                  child: Text(
                    focusedSec != null
                        ? '${focusedSec.numLabel} ${focusedSec.shortTitle} ×'
                        : 'All 01–09',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: focusedSec != null ? focalAccentFg : textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: bgBase,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderBright),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '✦ CO-DESIGN:',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('full_blueprint_global_chat_input'),
                          controller: _agentPromptController,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: textPrimary,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: focusedSec != null
                                ? 'Tell the Agent how to adjust ${focusedSec.numLabel} ${focusedSec.shortTitle} (or type a global change)...'
                                : 'Tell the Agent what to change across any section (or click a Bento card above to scope)...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 12,
                              color: textMuted,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 7),
                          ),
                          onSubmitted: (_) => submitDockChat(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        key: const ValueKey('full_blueprint_global_chat_send_btn'),
                        onTap:
                            widget.workbench.isAgentBusy ? null : submitDockChat,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Text(
                            widget.workbench.isAgentBusy ? '...' : 'Apply ↵',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
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

  // ── Tailored Bento Card Micro-Layouts (01..08) ─────────────────────────────
  Widget _buildSectionContentWidget(
    ProjectConceptBlueprint draft,
    int sectionIdx, {
    bool isReadOnlySummary = false,
  }) {
    switch (sectionIdx) {
      case 0: // 01 Goal — Lead Sentence + 3 Verb Pills
        return _buildStructuredGoalSection(
          draft,
          onEditTap: isReadOnlySummary
              ? null
              : () => _startInlineEdit(
                    'goal',
                    ProjectConceptBlueprint.sanitizeGoalText(draft.goal),
                  ),
        );
      case 1: // 02 Game Spec — 2×2 Tactile Spec Selector Tiles
        return _buildKvSpecGrid(
          isGameSpec: true,
          keys: const ['CAMERA VIEW', 'CONTROLS', 'PLAYER MODE', 'ARENA STRUCTURE'],
          values: draft.gameSpec,
        );
      case 2: // 03 Tech Spec — 2×2 Tactile Spec Selector Tiles
        return _buildKvSpecGrid(
          isGameSpec: false,
          keys: const ['ENGINE', 'PLATFORM', 'ASSET PIPELINE', 'NETWORK / SAVE'],
          values: draft.techSpec,
        );
      case 3: // 04 Design Pillars — 2-Line Scannable Stack
        return _buildDesignPillarCards(draft, isReadOnlySummary: isReadOnlySummary);
      case 4: // 05 Trade-Offs — Visual WIN › OVER › Strikethrough Rows
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
      case 5: // 06 Core Loop — E01..E0N Epic-Tagged Core Loop Beats
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
      case 6: // 07 Out of Scope — Muted Dashed Cut Chips
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
      case 7: // 08 Done When — Playtest Gate Callout Box
      default:
        return _buildCalloutStatement(
          draft.doneWhen,
          highlightMetrics: true,
          onEditTap: () => _startInlineEdit('done_when', draft.doneWhen),
        );
    }
  }

  // ── 01 Goal: Lead Sentence + 3 Compact Verb Pills ──────────────────────────
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
            SizedBox(
              height: 40,
              child: Text(
                headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                  color: textPrimary,
                ),
              ),
            ),
            if (clauses.isNotEmpty) ...[
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < clauses.length; i++) ...[
                    if (i > 0) const SizedBox(height: 5),
                    Container(
                      key: ValueKey('stage1_goal_clause_card_$i'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: bgRecessed,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: borderSubtle),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            (i + 1).toString().padLeft(2, '0'),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: textMuted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${clauses[i].title}: ${clauses[i].body}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                height: 1.35,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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

  // ── 08 Done When: Playtest Gate Callout Box ────────────────────────────────
  Widget _buildCalloutStatement(
    String statement, {
    required bool highlightMetrics,
    VoidCallback? onEditTap,
  }) {
    if (_activeInlineEditKey == 'done_when') {
      return _buildInlineEditorBox(
        editKey: 'done_when',
        onSave: (val) => widget.workbench.updateConceptDraft((d) => d.doneWhen = val),
      );
    }
    final barColor = highlightMetrics ? accentEmerald : borderBright;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEditTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bgRecessed,
            borderRadius: BorderRadius.circular(6),
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
                  fontSize: 13,
                  height: 1.48,
                )
              : Text(
                  statement,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.48,
                    color: textPrimary,
                  ),
                ),
        ),
      ),
    );
  }

  // ── 02 Game Spec & 03 Tech Spec: 2×2 Tactile Spec Selector Tiles ───────────
  Widget _buildKvSpecGrid({
    required bool isGameSpec,
    required List<String> keys,
    required List<String> values,
  }) {
    final pairs = List.generate(keys.length, (i) {
      final val = i < values.length ? values[i] : '—';
      return MapEntry(keys[i], val);
    });

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
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildKvCell(
                isGameSpec: isGameSpec,
                cellIndex: 1,
                k: pairs[1].key,
                v: pairs[1].value,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildKvCell(
                isGameSpec: isGameSpec,
                cellIndex: 2,
                k: pairs[2].key,
                v: pairs[2].value,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildKvCell(
                isGameSpec: isGameSpec,
                cellIndex: 3,
                k: pairs[3].key,
                v: pairs[3].value,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKvCell({
    required bool isGameSpec,
    required int cellIndex,
    required String k,
    required String v,
  }) {
    final editKey = 'kv_${isGameSpec ? "game" : "tech"}_$cellIndex';
    if (_activeInlineEditKey == editKey) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bgRecessed,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderBright),
        ),
        child: _buildInlineEditorBox(
          editKey: editKey,
          onSave: (val) => _applyDirectKvValue(
            isGameSpec: isGameSpec,
            cellIndex: cellIndex,
            newValue: val,
          ),
        ),
      );
    }

    final presets = _kvPresetsForCell(isGameSpec, cellIndex);
    return Material(
      color: bgRecessed,
      borderRadius: BorderRadius.circular(6),
      child: PopupMenuButton<String>(
        key: ValueKey('kv_cell_dropdown_${isGameSpec ? "game" : "tech"}_$cellIndex'),
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
                  fontSize: 12,
                  fontWeight: p == v ? FontWeight.w700 : FontWeight.w500,
                  color: p == v ? textPrimary : textSecondary,
                ),
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: '__custom__',
            child: Text(
              '✎ Custom Edit...',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderSubtle),
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
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: textMuted,
                      ),
                    ),
                  ),
                  Text(
                    '▾',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                v.trim().isEmpty ? 'Click to set...' : v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight:
                      v.trim().isEmpty ? FontWeight.w500 : FontWeight.w600,
                  fontStyle:
                      v.trim().isEmpty ? FontStyle.italic : FontStyle.normal,
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
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: 12,
          height: 1.38,
          color: textPrimary,
        ),
      );
    }

    final leadIn = rawText.substring(0, colonIdx);
    final rest = rawText.substring(colonIdx + 1).trim();

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 12,
          height: 1.38,
        ),
        children: [
          TextSpan(
            text: '$leadIn — ',
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

  // ── 04 Design Pillars: 2-Line Scannable Stack ──────────────────────────────
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
          padding: const EdgeInsets.symmetric(vertical: 4),
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
            margin: EdgeInsets.only(bottom: idx < pillars.length - 1 ? 7 : 0),
            padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2, right: 4),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: borderBright, width: 2),
              ),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1.5),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          height: 1.35,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isReadOnlySummary && pillars.length > 1) ...[
                  const SizedBox(width: 6),
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
                          fontSize: 12,
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
          const SizedBox(height: 8),
          if (_activeInlineEditKey == 'add_pillar')
            _buildInlineEditorBox(
              editKey: 'add_pillar',
              hintText: 'Type a new Design Pillar (e.g. Every Choice Echoes: Visible arena feedback)...',
              onSave: (val) => widget.workbench.updateConceptDraft((d) {
                d.designPillars = [
                  ...d.designPillars,
                  ProjectConceptBlueprint.ensureNamedPillar(
                    val,
                    d.designPillars.length,
                  ),
                ];
              }),
            )
          else
            _buildInlineAddBar(
              barKey: const ValueKey('section_3_add_pillar_btn'),
              label: '+ Add Design Pillar...',
              onTap: () => _startInlineEdit('add_pillar', ''),
            ),
        ],
      ],
    );
  }

  Widget _buildInlineAddBar({
    Key? barKey,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgRecessed.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        key: barKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: borderSubtle),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '+ Add',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 06 Core Loop: Connected E01..E0N Epic Timeline Rows ────────────────────
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
          if (i > 0) const SizedBox(height: 5),
          if (_activeInlineEditKey == 'indexed_${prefix.toLowerCase()}_$i' &&
              onEditItem != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
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
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: bgRecessed,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: borderSubtle),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: bgSurface,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: borderBright),
                        ),
                        child: Text(
                          isCoreLoop
                              ? 'E${(i + 1).toString().padLeft(2, '0')}'
                              : '$prefix·${(i + 1).toString().padLeft(2, '0')}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildFormattedLeadInText(items[i]),
                      ),
                      if (onReorderItem != null && items.length > 1) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          key: ValueKey('core_loop_move_up_$i'),
                          onTap: i > 0 ? () => onReorderItem(i, i - 1) : null,
                          borderRadius: BorderRadius.circular(3),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 1,
                            ),
                            child: Text(
                              '↑',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 1,
                            ),
                            child: Text(
                              '↓',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
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
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => onDeleteItem(i),
                          borderRadius: BorderRadius.circular(3),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            child: Text(
                              '×',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
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
        if (onAddSave != null) ...[
          const SizedBox(height: 7),
          if (_activeInlineEditKey == 'add_beat')
            _buildInlineEditorBox(
              editKey: 'add_beat',
              hintText: 'Type a Core Loop Beat (e.g. Extract & Upgrade: Spend gathered ore)...',
              onSave: onAddSave,
            )
          else
            _buildInlineAddBar(
              barKey: const ValueKey('section_5_add_beat_btn'),
              label: isCoreLoop
                  ? '+ Add Core Loop Beat...'
                  : '+ Add item...',
              onTap: () => _startInlineEdit('add_beat', ''),
            ),
        ],
      ],
    );
  }

  // ── 05 Trade-Offs: Visual WIN › OVER › Strikethrough Rows ──────────────────
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
          if (i > 0) const SizedBox(height: 6),
          if (_activeInlineEditKey == 'tradeoff_$i' && onEditItem != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _buildInlineEditorBox(
                editKey: 'tradeoff_$i',
                onSave: (val) => onEditItem(i, val),
              ),
            )
          else
            _buildSingleTradeOffBar(
              tradeOffs[i],
              onTap: onEditItem == null
                  ? null
                  : () => _startInlineEdit('tradeoff_$i', tradeOffs[i]),
              onDelete: onDeleteItem == null ? null : () => onDeleteItem(i),
            ),
        ],
        if (onAddSave != null) ...[
          const SizedBox(height: 7),
          if (_activeInlineEditKey == 'add_tradeoff')
            _buildInlineEditorBox(
              editKey: 'add_tradeoff',
              hintText: 'Type X over Y trade-off (e.g. Immediate arcade feel over simulation depth)...',
              onSave: onAddSave,
            )
          else
            _buildInlineAddBar(
              barKey: const ValueKey('section_4_add_guardrail_btn'),
              label: '+ Add Trade-Off (X over Y)...',
              onTap: () => _startInlineEdit('add_tradeoff', ''),
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
    final loseText = parts.length > 1
        ? parts.sublist(1).join(' over ').trim()
        : 'secondary complexity';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: bgRecessed,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: borderSubtle),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  winText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: accentEmerald.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'OVER',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: accentEmerald,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  loseText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: textMuted,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: textMuted.withValues(alpha: 0.7),
                  ),
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    child: Text(
                      '×',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
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

  // ── 07 Out of Scope: Muted Cut Chips ───────────────────────────────────────
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
          padding: const EdgeInsets.symmetric(vertical: 4),
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
          borderRadius: BorderRadius.circular(5),
          child: Container(
            margin: EdgeInsets.only(bottom: idx < exclusions.length - 1 ? 5 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: bgRecessed.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: borderSubtle),
            ),
            child: Row(
              children: [
                Text(
                  '✕',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: accentAmber,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exclusions[idx],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: textSecondary,
                    ),
                  ),
                ),
                if (onDeleteItem != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => onDeleteItem(idx),
                    borderRadius: BorderRadius.circular(3),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 1,
                      ),
                      child: Text(
                        '×',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
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
        if (onAddSave != null) ...[
          const SizedBox(height: 7),
          if (_activeInlineEditKey == 'add_exclusion')
            _buildInlineEditorBox(
              editKey: 'add_exclusion',
              hintText: 'Type an Out of Scope exclusion (e.g. No multiplayer networking in v0.1)...',
              onSave: onAddSave,
            )
          else
            _buildInlineAddBar(
              barKey: const ValueKey('section_6_add_cut_btn'),
              label: '+ Add Out of Scope Cut...',
              onTap: () => _startInlineEdit('add_exclusion', ''),
            ),
        ],
      ],
    );
  }
}
