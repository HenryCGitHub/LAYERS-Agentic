part of 'release_workbench_screen.dart';

extension _WorkbenchCheckpointWorkspaceExt on _ReleaseWorkbenchScreenState {
  void _completeAllCheckpointTasks(FeatureStateNode node) {
    node.flattenLegacyNestedChecklistIfNeeded();
    for (final task in node.checklist) {
      task.completed = true;
      for (final child in task.children) {
        child.completed = true;
      }
    }
    for (int gIdx = 0; gIdx < node.edgeCases.length; gIdx++) {
      node.setGuardSignedOff(gIdx, node.edgeCases[gIdx], true);
    }
    node.isPlaytestPassed = true;
  }

  void _passCheckpointPlaytestAndAdvance(
    TierDocument feat,
    List<FeatureStateNode> states,
    FeatureStateNode node,
  ) {
    if (node.isPlaytestPassed || node.isCompleted) {
      node.isPlaytestPassed = false;
      _rebuild(() {
        _awaitingPlaytestVerification.remove(node.id);
        _inlineBugDrawerNodeId = null;
      });
      widget.workbench.updateFeatureStates(feat.id, states);
      return;
    }

    _completeAllCheckpointTasks(node);
    final activeVer = widget.workbench.activeReleaseVersionTag;
    int nextCpIdx = states.indexWhere(
      (s) => s.releaseVersion == activeVer && !s.isCompleted,
    );
    if (nextCpIdx == -1) {
      nextCpIdx = states.indexWhere((s) => !s.isCompleted);
    }
    _rebuild(() {
      _awaitingPlaytestVerification.remove(node.id);
      _inlineBugDrawerNodeId = null;
      if (nextCpIdx != -1) {
        _manualCheckpointFocusIndex = nextCpIdx;
        _manualCheckpointFocusFeatureId = feat.id;
      } else {
        _manualCheckpointFocusIndex = null;
        _manualCheckpointFocusFeatureId = null;
      }
    });
    widget.workbench.updateFeatureStates(feat.id, states);

    if (widget.workbench.getDocumentProgress(feat.id) >= 100 ||
        states.every((s) => s.isCompleted)) {
      _rebuild(() {
        _manualCheckpointFocusIndex = null;
        _manualCheckpointFocusFeatureId = null;
      });
      final nextFeat = widget.workbench.nextIncompleteFeature;
      if (nextFeat != null && nextFeat.id != feat.id) {
        widget.workbench.selectFeature(nextFeat.id);
      }
    }
  }

  Widget _buildUnifiedDoneButton({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required FeatureStateNode node,
    required bool isHalfScreenOverlayMode,
  }) {
    final bool isVerifiedDoneState = node.isPlaytestPassed || node.isCompleted;
    final String label = isVerifiedDoneState
        ? '✓ Passed'
        : (isHalfScreenOverlayMode
            ? '✓ Pass & Next →'
            : '✓ Pass Playtest & Next →');

    return InkWell(
      key: ValueKey('one_click_complete_next_btn_${node.id}'),
      onTap: () => _passCheckpointPlaytestAndAdvance(feat, states, node),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isHalfScreenOverlayMode ? 9 : 12,
          vertical: isHalfScreenOverlayMode ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: isVerifiedDoneState
              ? const Color(0xFF10B981).withValues(alpha: 0.18)
              : const Color(0xFF10B981),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isVerifiedDoneState
                ? const Color(0xFF10B981).withValues(alpha: 0.45)
                : const Color(0xFF34D399),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isHalfScreenOverlayMode ? fontMicro : fontBody,
            fontWeight: weightBold,
            color: isVerifiedDoneState
                ? const Color(0xFF6EE7B7)
                : const Color(0xFF042117),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureActionsMenu({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required FeatureStateNode node,
    required bool isHalfScreen,
  }) {
    final bool isPassed = node.isPlaytestPassed || node.isCompleted;
    return PopupMenuButton<String>(
      key: isHalfScreen
          ? ValueKey('halfscreen_feature_actions_menu_btn_${feat.id}')
          : ValueKey('desktop_feature_actions_menu_btn_${feat.id}'),
      tooltip: 'Feature actions',
      color: bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderBright),
      ),
      onSelected: (action) {
        if (action == 'copy_ai_prompt') {
          _copyActiveFeaturePrompt(feat);
        } else if (action == 'log_issue') {
          _rebuild(() {
            _inlineBugDrawerNodeId =
                _inlineBugDrawerNodeId == node.id ? null : node.id;
            _inlineBugInputCtrl.clear();
          });
        } else if (action == 'connect_godot') {
          showConnectGodotPluginDialog(context, widget.workbench);
        } else if (action == 'rename_feature') {
          _startStage2InlineEdit('rename_header_feat_${feat.id}', feat.title);
        } else if (action == 'feature_inbox') {
          _showFeatureInboxModal(context, preferredBeatId: feat.parentId);
        } else if (action == 'toggle_complete_all') {
          final targetPassed = !isPassed;
          node.flattenLegacyNestedChecklistIfNeeded();
          node.isPlaytestPassed = targetPassed;
          if (targetPassed) {
            for (final task in node.checklist) {
              task.completed = true;
              for (final child in task.children) {
                child.completed = true;
              }
            }
            for (int gIdx = 0; gIdx < node.edgeCases.length; gIdx++) {
              node.setGuardSignedOff(gIdx, node.edgeCases[gIdx], true);
            }
          }
          _rebuild(() {
            _awaitingPlaytestVerification.remove(node.id);
          });
          widget.workbench.updateFeatureStates(feat.id, states);
        } else if (action == 'archive_pivot') {
          widget.workbench.toggleSupersedeFeature(
            feat.id,
            pivotReason: 'Archived from Feature Header',
          );
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          value: 'copy_ai_prompt',
          height: 34,
          child: Text(
            '⧉ Copy Feature Spec',
            style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
          ),
        ),
        PopupMenuItem<String>(
          value: 'log_issue',
          height: 34,
          child: Text(
            '⚑ Log Playtest Issue',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFFFBBF24),
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'feature_inbox',
          height: 34,
          child: Text(
            '📬 Feature Inbox',
            style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'connect_godot',
          height: 34,
          child: Text(
            '🔌 Connect Godot 4 Plugin',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFF7DD3FC),
            ),
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'toggle_complete_all',
          height: 34,
          child: Text(
            isPassed ? '↺ Mark Feature Unpassed' : '✓ Toggle Feature Passed',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: isPassed ? textSecondary : accentEmerald,
            ),
          ),
        ),
        PopupMenuItem<String>(
          value: 'rename_feature',
          height: 34,
          child: Text(
            '✎ Rename Feature',
            style: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
          ),
        ),
        PopupMenuItem<String>(
          value: 'archive_pivot',
          height: 34,
          child: Text(
            'Archive / Pivot Feature',
            style: GoogleFonts.inter(fontSize: 12.5, color: accentCrimson),
          ),
        ),
      ],
      child: Container(
        width: isHalfScreen ? 24 : 26,
        height: isHalfScreen ? 24 : 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isHalfScreen ? bgSurface : const Color(0xFF181E2C),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isHalfScreen ? borderBright : const Color(0xFF262E40),
          ),
        ),
        child: Text(
          '⋯',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedFeatureHeader({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int index,
    required FeatureStateNode node,
    required bool isHalfScreenOverlayMode,
    required String epicShortCode,
    required String featShortTitle,
    required Widget doneBtn,
    required Widget featureActionsMenu,
  }) {
    final bool isRenamingHeaderFeat =
        _activeStage2InlineEditKey == 'rename_header_feat_${feat.id}';
    final bool isDrawerOpen = _inlineBugDrawerNodeId == node.id;
    final bool isPassed = node.isPlaytestPassed || node.isCompleted;

    final String statusLabel = isPassed ? 'Passed ✓' : 'Queued';
    final Color statusColor = isPassed
        ? accentEmerald
        : const Color(0xFF94A3B8);

    return Container(
      key: ValueKey('unified_header_${node.id}'),
      padding: EdgeInsets.fromLTRB(
        isHalfScreenOverlayMode ? 12 : 16,
        10,
        isHalfScreenOverlayMode ? 12 : 16,
        10,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0E131D),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isHalfScreenOverlayMode)
                    InkWell(
                      key: ValueKey('halfscreen_outliner_trigger_${node.id}'),
                      onTap: () {
                        _rebuild(() {
                          _isHalfScreenOutlinerOpen =
                              !_isHalfScreenOutlinerOpen;
                        });
                      },
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bgSurface,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: _isHalfScreenOutlinerOpen
                                ? accentEmerald
                                : borderBright,
                          ),
                        ),
                        child: Text(
                          '☰',
                          style: GoogleFonts.inter(
                            fontSize: fontBody,
                            fontWeight: weightSemi,
                            color: _isHalfScreenOutlinerOpen
                                ? textPrimary
                                : textSecondary,
                          ),
                        ),
                      ),
                    ),
                  if (isRenamingHeaderFeat)
                    SizedBox(
                      width: 220,
                      child: _buildStage2InlineEditor(
                        editKey: 'rename_header_feat_${feat.id}',
                        inputKey: const ValueKey(
                          'workbench_rename_live_feature_input',
                        ),
                        saveBtnKey: const ValueKey(
                          'confirm_workbench_rename_live_feature_btn',
                        ),
                        hintText: 'Feature title...',
                        onSave: (val) =>
                            widget.workbench.renameLiveFeature(feat.id, val),
                      ),
                    )
                  else
                    InkWell(
                      key: ValueKey('workbench_rename_feature_btn_${feat.id}'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _startStage2InlineEdit(
                        'rename_header_feat_${feat.id}',
                        feat.title,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 1,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$epicShortCode › ',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: fontMicro,
                                fontWeight: weightSemi,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: isHalfScreenOverlayMode ? 180 : 280,
                              ),
                              child: Text(
                                featShortTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: fontBody,
                                  fontWeight: weightBold,
                                  color: const Color(0xFFF8FAFC),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '✎',
                              style: GoogleFonts.inter(
                                fontSize: fontMicro,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Container(
                    key: ValueKey('feature_status_badge_${node.id}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.38),
                      ),
                    ),
                    child: Text(
                      statusLabel,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9.5,
                        fontWeight: weightBold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InkWell(
                    key: ValueKey('connect_godot_plugin_chip_${node.id}'),
                    borderRadius: BorderRadius.circular(5),
                    onTap: () =>
                        showConnectGodotPluginDialog(context, widget.workbench),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07090E),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '🔌 Godot',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: weightSemi,
                          color: const Color(0xFF7DD3FC),
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    key: ValueKey('feature_header_copy_spec_btn_${node.id}'),
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => _copyActiveFeaturePrompt(feat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07090E),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: const Color(0xFF334155),
                        ),
                      ),
                      child: Text(
                        '⧉ Copy Spec',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: weightSemi,
                          color: const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    key: ValueKey('feature_gate_log_bug_btn_${node.id}'),
                    borderRadius: BorderRadius.circular(5),
                    onTap: () {
                      _rebuild(() {
                        if (isDrawerOpen) {
                          _inlineBugDrawerNodeId = null;
                        } else {
                          _inlineBugDrawerNodeId = node.id;
                          _inlineBugInputCtrl.clear();
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4.5,
                      ),
                      decoration: BoxDecoration(
                        color: isDrawerOpen
                            ? const Color(0xFFFBBF24).withValues(alpha: 0.14)
                            : const Color(0xFF181E2C),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: isDrawerOpen
                              ? const Color(0xFFFBBF24).withValues(alpha: 0.45)
                              : const Color(0xFF262E40),
                        ),
                      ),
                      child: Text(
                        '⚑ Issue',
                        style: GoogleFonts.inter(
                          fontSize: fontMicro,
                          fontWeight: weightSemi,
                          color: isDrawerOpen
                              ? const Color(0xFFFCD34D)
                              : const Color(0xFFFBBF24),
                        ),
                      ),
                    ),
                  ),
                  doneBtn,
                  featureActionsMenu,
                ],
              ),
            ],
          ),
          if (states.length > 1 ||
              widget.workbench
                  .scheduledInboxUpgradesForFeature(feat.id)
                  .isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (states.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07090E),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (int cpIdx = 0; cpIdx < states.length; cpIdx++) ...[
                          if (cpIdx > 0)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: Text(
                                '→',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  color: const Color(0xFF475569),
                                ),
                              ),
                            ),
                          InkWell(
                            key: ValueKey(
                              isHalfScreenOverlayMode
                                  ? 'halfscreen_cp_${feat.id}_$cpIdx'
                                  : 'outline_cp_${feat.id}_$cpIdx',
                            ),
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              _rebuild(() {
                                _manualCheckpointFocusIndex = cpIdx;
                                _manualCheckpointFocusFeatureId = feat.id;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cpIdx == index
                                    ? const Color(0xFF38BDF8)
                                        .withValues(alpha: 0.14)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: cpIdx == index
                                      ? const Color(0xFF38BDF8)
                                          .withValues(alpha: 0.42)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                'CP${cpIdx + 1} · ${states[cpIdx].releaseVersion}${states[cpIdx].isCompleted ? ' ✓' : ''}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: cpIdx == index
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: cpIdx == index
                                      ? const Color(0xFF7DD3FC)
                                      : (states[cpIdx].isCompleted
                                          ? const Color(0xFF6EE7B7)
                                          : const Color(0xFF94A3B8)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                for (final upg in widget.workbench
                    .scheduledInboxUpgradesForFeature(feat.id))
                  InkWell(
                    key: ValueKey(
                      isHalfScreenOverlayMode
                          ? 'halfscreen_scheduled_inbox_chip_${feat.id}_${upg.id}'
                          : 'desktop_scheduled_inbox_chip_${feat.id}_${upg.id}',
                    ),
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _showFeatureInboxModal(
                      context,
                      preferredBeatId: feat.parentId,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accentEmerald.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: accentEmerald.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        '🗓 Queued · ${upg.targetFuturePhase.shortName}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: accentEmerald,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveSynthesisPlaceholder({
    required TierDocument feat,
    required bool isSynthesizingFeatureNow,
  }) {
    return Container(
      key: ValueKey('feature_steps_in_progress_${feat.id}'),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 18),
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderSubtle),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: isSynthesizingFeatureNow
                  ? const Color(0xFFFBBF24)
                  : textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isSynthesizingFeatureNow
                ? 'Drafting ${feat.title} Brief…'
                : '${feat.title} — Drafting Brief',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Preparing plain-English Goal, In Scope, and Done When playtest criteria…',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlinePlaytestBugDrawer({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int index,
    required FeatureStateNode node,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF191412),
        border: Border(bottom: BorderSide(color: Color(0x4DF59E0B))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Log Playtest Issue:',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFBBF24),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Focus(
                  onKeyEvent: (_, event) => handleEnterSubmitShiftNewline(
                    event,
                    _inlineBugInputCtrl,
                    onSubmit: () =>
                        _submitInlinePlaytestBug(feat, states, index, node),
                  ),
                  child: TextField(
                    key: ValueKey('feature_gate_bug_input_${node.id}'),
                    controller: _inlineBugInputCtrl,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: GoogleFonts.inter(fontSize: 12.5, color: textPrimary),
                    decoration: InputDecoration(
                      hintText:
                          'Describe bug, feel tweak, or paste Godot Debugger trace (res://...gd:42) — Shift+Enter for new line...',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
                      filled: true,
                      fillColor: bgRecessed,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: borderSubtle),
                      ),
                    ),
                    onSubmitted: (_) =>
                        _submitInlinePlaytestBug(feat, states, index, node),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: ValueKey('feature_gate_bug_submit_btn_${node.id}'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => _submitInlinePlaytestBug(feat, states, index, node),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    '+ Log Issue',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFBBF24),
                    ),
                  ),
                ),
              ),
            ],
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _inlineBugInputCtrl,
            builder: (ctx, val, _) {
              final parsed = GodotGdscriptGuard.parseDebuggerTrace(val.text);
              if (parsed == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  key: ValueKey('debugger_trace_chip_${node.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.38),
                    ),
                  ),
                  child: Text(
                    parsed.summaryChipLabel,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF7DD3FC),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCheckpointCard(
    TierDocument feat,
    List<FeatureStateNode> states,
    int index, {
    required int activeFocusIndex,
    bool isHalfScreenOverlayMode = false,
    bool fillViewportHeight = false,
  }) {
    if (widget.workbench.focusMode && index != activeFocusIndex) {
      return const SizedBox.shrink();
    }

    final node = states[index];
    final beatsForBreadcrumb = widget.workbench.activeReleaseBeats;
    int parentBeatIdx = 0;
    String? parentBeatTitle;
    for (int bIdx = 0; bIdx < beatsForBreadcrumb.length; bIdx++) {
      if (beatsForBreadcrumb[bIdx].id == feat.parentId) {
        parentBeatIdx = bIdx;
        parentBeatTitle = beatsForBreadcrumb[bIdx].title;
        break;
      }
    }
    final epicShortCode = 'E${(parentBeatIdx + 1).toString().padLeft(2, '0')}';
    final cleanEpicTitle = parentBeatTitle != null
        ? _formatOutlineBeatDisplayTitle(parentBeatTitle)
        : 'Core Loop';
    final featShortTitle = _formatOutlineFeatureDisplayTitle(
      feat.title,
      parentBeatTitle,
      beatIndex: parentBeatIdx,
    );

    final isFeatureBeingBuiltInLiveMode =
        widget.workbench.isFeatureBeingBuiltInLiveMode(feat.id);
    final isSynthesizingFeatureNow =
        widget.workbench.isSynthesizingFeatureSteps(feat.id);

    final Widget doneBtn = _buildUnifiedDoneButton(
      feat: feat,
      states: states,
      node: node,
      isHalfScreenOverlayMode: isHalfScreenOverlayMode,
    );
    final Widget featureActionsMenu = _buildFeatureActionsMenu(
      feat: feat,
      states: states,
      node: node,
      isHalfScreen: isHalfScreenOverlayMode,
    );

    final isDrawerOpen = _inlineBugDrawerNodeId == node.id;

    final Widget bodyContent = isFeatureBeingBuiltInLiveMode
        ? Padding(
            padding: EdgeInsets.all(isHalfScreenOverlayMode ? 12 : 16),
            child: _buildLiveSynthesisPlaceholder(
              feat: feat,
              isSynthesizingFeatureNow: isSynthesizingFeatureNow,
            ),
          )
        : _buildPlaytestGateWorkspacePane(
            feat: feat,
            states: states,
            checkpointIndex: index,
            node: node,
            epicShortCode: epicShortCode,
            epicTitle: cleanEpicTitle,
          );

    return Container(
      key: ValueKey('checkpoint_single_col_$index'),
      margin: const EdgeInsets.only(bottom: 6),
      child: Container(
        key: ValueKey('checkpoint_spec_pane_$index'),
        child: Container(
          key: ValueKey('pinned_active_step_window_${node.id}'),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0D14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF1F2B3E),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildUnifiedFeatureHeader(
                feat: feat,
                states: states,
                index: index,
                node: node,
                isHalfScreenOverlayMode: isHalfScreenOverlayMode,
                epicShortCode: epicShortCode,
                featShortTitle: featShortTitle,
                doneBtn: doneBtn,
                featureActionsMenu: featureActionsMenu,
              ),
              if (isDrawerOpen)
                _buildInlinePlaytestBugDrawer(
                  feat: feat,
                  states: states,
                  index: index,
                  node: node,
                ),
              if (fillViewportHeight)
                Expanded(
                  child: SingleChildScrollView(
                    child: bodyContent,
                  ),
                )
              else
                bodyContent,
            ],
          ),
        ),
      ),
    );
  }
}
