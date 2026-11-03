part of 'release_workbench_screen.dart';

extension _WorkbenchOutlinerAndShellExt on _ReleaseWorkbenchScreenState {
  void _startStage2InlineEdit(String key, String initialText) {
    _rebuild(() {
      _activeStage2InlineEditKey = key;
      _stage2InlineEditController.text = initialText;
      _stage2InlineEditController.selection = TextSelection.fromPosition(
        TextPosition(offset: _stage2InlineEditController.text.length),
      );
    });
  }

  Widget _buildStage2InlineEditor({
    required String editKey,
    required ValueKey<String> inputKey,
    required ValueKey<String> saveBtnKey,
    required ValueChanged<String> onSave,
    String hintText = 'Enter title...',
    VoidCallback? onDelete,
    ValueKey<String>? deleteBtnKey,
  }) {
    void commitSave() {
      final trimmed = _stage2InlineEditController.text.trim();
      _rebuild(() {
        _activeStage2InlineEditKey = null;
      });
      if (trimmed.isNotEmpty) {
        onSave(trimmed);
      }
    }

    void cancelEdit() {
      _rebuild(() {
        _activeStage2InlineEditKey = null;
      });
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: textPrimary.withValues(alpha: 0.65),
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
                key: inputKey,
                controller: _stage2InlineEditController,
                autofocus: true,
                style: GoogleFonts.inter(fontSize: 12.5, color: textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hintText,
                  hintStyle: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 3),
                ),
                onSubmitted: (_) => commitSave(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            key: saveBtnKey,
            onTap: commitSave,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                '✓',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 4),
            InkWell(
              key: deleteBtnKey,
              onTap: () {
                _rebuild(() {
                  _activeStage2InlineEditKey = null;
                });
                onDelete();
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 13,
                  color: accentCrimson,
                ),
              ),
            ),
          ],
          const SizedBox(width: 4),
          InkWell(
            onTap: cancelEdit,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '×',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
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

  void _commitInlineAddBuildTask(
    TierDocument feat,
    List<FeatureStateNode> states,
    int cpIdx,
    String rawTitle,
  ) {
    final trimmed = rawTitle.trim();
    if (trimmed.isEmpty || cpIdx < 0 || cpIdx >= states.length) return;
    final cpNode = states[cpIdx];
    final newIdx = widget.workbench.addBuildTaskToCheckpointWithAi(
      featureId: feat.id,
      states: states,
      checkpointIndex: cpIdx,
      rawTaskTitle: trimmed,
      unrealCppMode: _unrealCppMode,
    );
    if (newIdx < 0) return;
    _rebuild(() {
      _manualCheckpointFocusIndex = cpIdx;
      _manualCheckpointFocusFeatureId = feat.id;
      _selectedTaskIndexByCheckpoint[cpNode.id] = newIdx;
      _selectedSubStepIndexByTask['${cpNode.id}_$newIdx'] = 0;
    });
  }

  Widget _buildLeftBeatFeatureRail(
    TierDocument rel, {
    bool isOverlayDrawer = false,
  }) {
    final beats = widget.workbench.activeReleaseBeats;
    final relProgress = widget.workbench.getDocumentProgress(rel.id);
    final releases = widget.workbench.projectReleases;
    final archivedFeats = widget.workbench.supersededFeatures;
    final activeVer = widget.workbench.activeReleaseVersionTag;
    final releaseRemMins = _computeReleaseRemainingMinutes(beats);
    final releaseRemHoursStr =
        TaskHowToBlueprint.formatRemainingHoursShort(releaseRemMins);
    final isReleaseDone = relProgress >= 100 || releaseRemMins <= 0;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.max,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          color: bgRecessed,
          child: Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Release Selector Dropdown Pill ("v0.1 Prototype ▾")
                  Flexible(
                    child: PopupMenuButton<String>(
                      key: const ValueKey('release_selector_dropdown_btn'),
                      color: bgSurface,
                      tooltip: 'Switch Release View or Evolve Scope',
                      onSelected: (value) {
                        if (value == '__progressive_release__') {
                          _showProgressiveNextReleaseModal(context);
                        } else if (value == '__view_release_plan__') {
                          _showSavedReleasePlanDialog(context, rel);
                        } else if (value.startsWith('rel:')) {
                          final targetId = value.substring(4);
                          final targetDoc = widget.workbench.documents[targetId];
                          if (targetDoc != null &&
                              targetDoc.childrenIds.isEmpty &&
                              targetId != rel.id) {
                            _showProgressiveNextReleaseModal(context);
                          } else {
                            _rebuild(() {
                              _manualCheckpointFocusIndex = null;
                              _manualCheckpointFocusFeatureId = null;
                            });
                            widget.workbench.selectActiveRelease(targetId);
                          }
                        } else {
                          widget.workbench.setReleaseViewFilter(value);
                        }
                      },
                      itemBuilder: (context) {
                        final builtReleases = releases
                            .where((r) => r.childrenIds.isNotEmpty)
                            .toList();
                        final displayReleases = builtReleases.isNotEmpty
                            ? builtReleases
                            : releases;
                        final isRelComplete =
                            widget.workbench.isActiveReleaseComplete;

                        final byPhase = <ProductionPhase, List<TierDocument>>{
                          for (final p in ProductionPhase.values) p: <TierDocument>[],
                        };
                        for (final r in displayReleases) {
                          final p = widget.workbench.releasePhaseFor(r);
                          byPhase[p]!.add(r);
                        }

                        String phaseGroupHeader(ProductionPhase p) {
                          switch (p) {
                            case ProductionPhase.prototype:
                              return '01 · PROTOTYPE (GREYBOX LOOP)';
                            case ProductionPhase.mvp:
                              return '02 · MVP (FUNCTIONAL DEPTH)';
                            case ProductionPhase.verticalSlice:
                              return '03 · VERTICAL SLICE (POLISH PASS)';
                            case ProductionPhase.fullProduction:
                              return '04 · FULL PRODUCTION (V1.0 CONTENT)';
                            case ProductionPhase.postLaunch:
                              return '05 · POST-LAUNCH & LIVE OPS (V1.1+)';
                          }
                        }

                        final menuItems = <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            enabled: false,
                            height: 26,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'RELEASES · BY PHASE',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.9,
                                    color: textMuted,
                                  ),
                                ),
                                Text(
                                  '${displayReleases.length} Shipped',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ];

                        for (final phase in ProductionPhase.values) {
                          final groupRels = byPhase[phase]!;
                          final hasActiveInGroup =
                              groupRels.any((r) => r.id == rel.id);
                          if (groupRels.isEmpty) {
                            menuItems.add(
                              PopupMenuItem<String>(
                                enabled: false,
                                height: 22,
                                child: Text(
                                  '${phaseGroupHeader(phase)} — UPCOMING',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: textMuted.withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                            );
                            continue;
                          }

                          final doneInGroup = groupRels
                              .where(
                                (r) =>
                                    widget.workbench.getDocumentProgress(r.id) >=
                                    100,
                              )
                              .length;
                          menuItems.add(
                            PopupMenuItem<String>(
                              enabled: false,
                              height: 24,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      phaseGroupHeader(phase),
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 9.5,
                                        fontWeight: hasActiveInGroup
                                            ? FontWeight.w800
                                            : FontWeight.w700,
                                        color: hasActiveInGroup
                                            ? textPrimary
                                            : textMuted,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    hasActiveInGroup
                                        ? 'ACTIVE'
                                        : '$doneInGroup / ${groupRels.length}',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: hasActiveInGroup
                                          ? textPrimary
                                          : textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );

                          for (final r in groupRels) {
                            final isCurrent = r.id == rel.id;
                            final rVer =
                                widget.workbench.releaseVersionTagFor(r);
                            final rDisplayName =
                                widget.workbench.releaseDisplayName(r);
                            final rProg =
                                widget.workbench.getDocumentProgress(r.id);
                            menuItems.add(
                              PopupMenuItem<String>(
                                value: 'rel:${r.id}',
                                height: 36,
                                child: Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? bgRecessed
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(5),
                                    border: isCurrent
                                        ? Border.all(
                                            color: borderBright,
                                          )
                                        : Border(
                                            left: BorderSide(
                                              color: hasActiveInGroup
                                                  ? borderBright
                                                  : borderSubtle,
                                              width: 2,
                                            ),
                                          ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              isCurrent ? '● ' : '✓ ',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: isCurrent
                                                    ? textPrimary
                                                    : textMuted,
                                              ),
                                            ),
                                            Text(
                                              '$rVer ',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 11,
                                                fontWeight: isCurrent
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                                color: isCurrent
                                                    ? textPrimary
                                                    : textSecondary,
                                              ),
                                            ),
                                            Flexible(
                                              child: Text(
                                                rDisplayName,
                                                style: GoogleFonts.inter(
                                                  fontSize: 11.5,
                                                  fontWeight: isCurrent
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: isCurrent
                                                      ? textPrimary
                                                      : textMuted,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      if (isCurrent)
                                        Text(
                                          '$relProgress% · $releaseRemHoursStr left',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: textSecondary,
                                          ),
                                        )
                                      else
                                        Text(
                                          '$rProg%',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: textMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                        }

                        if (builtReleases.length > 1 ||
                            widget.workbench.releaseViewFilter != 'active') {
                          final currentFilter =
                              widget.workbench.releaseViewFilter;
                          menuItems.add(const PopupMenuDivider());
                          menuItems.add(
                            PopupMenuItem<String>(
                              value: 'active',
                              height: 32,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '🎯 Active Milestone Only ($activeVer)',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        fontWeight: currentFilter == 'active'
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: currentFilter == 'active'
                                            ? textPrimary
                                            : textSecondary,
                                      ),
                                    ),
                                  ),
                                  if (currentFilter == 'active')
                                    Text(
                                      '✓',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                          menuItems.add(
                            PopupMenuItem<String>(
                              value: 'all',
                              height: 32,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '🌐 All Live Game Features (Include STABLE ✓)',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        fontWeight: currentFilter == 'all'
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: currentFilter == 'all'
                                            ? textPrimary
                                            : textSecondary,
                                      ),
                                    ),
                                  ),
                                  if (currentFilter == 'all')
                                    Text(
                                      '✓',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }

                        if (archivedFeats.isNotEmpty) {
                          menuItems.add(const PopupMenuDivider());
                          menuItems.add(
                            PopupMenuItem<String>(
                              value: 'archived',
                              child: Text(
                                '🗄 Superseded Testbeds Archive (${archivedFeats.length})',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: textSecondary,
                                ),
                              ),
                            ),
                          );
                        }

                        menuItems.add(const PopupMenuDivider());
                        menuItems.add(
                          PopupMenuItem<String>(
                            value: '__view_release_plan__',
                            height: 36,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    '📋 View $activeVer Release Plan',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Saved Ledger',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                        menuItems.add(
                          PopupMenuItem<String>(
                            value: '__progressive_release__',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: bgRecessed,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: borderSubtle),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      isRelComplete
                                          ? '+ Plan Next Release (${widget.workbench.nextProgressiveVersionLabel})'
                                          : '🔒 Complete $activeVer ($relProgress%) to unlock ${widget.workbench.nextProgressiveVersionLabel}',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isRelComplete
                                            ? const Color(0xFF10B981)
                                            : textMuted,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isRelComplete ? 'AI Co-Pilot ✦' : 'LOCKED',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: isRelComplete
                                          ? const Color(0xFF10B981)
                                          : textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        return menuItems;
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 3,
                        ),
                        child: LayoutBuilder(
                          builder: (context, pillConstraints) {
                            final showPhaseChip =
                                pillConstraints.maxWidth >= 130;
                            final richLabel = RichText(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                                children: [
                                  TextSpan(
                                    text: '$activeVer ',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        '${widget.workbench.releaseDisplayName(rel)} ▾',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (!showPhaseChip) {
                              return richLabel;
                            }
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.workbench.releasePhaseShortBadge(rel),
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: textMuted,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(child: richLabel),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Right: Simple Number-Only Live Rollup ("12h Left #%"), plus Close button in Half-Screen Slide-Over mode
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RichText(
                        key: const ValueKey('outline_release_eta_summary'),
                        text: TextSpan(
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: isReleaseDone ? textPrimary : textMuted,
                          ),
                          children: [
                            TextSpan(text: '$releaseRemHoursStr Left '),
                            TextSpan(
                              text: '$relProgress%',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isReleaseDone
                                    ? textPrimary
                                    : textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isOverlayDrawer) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          key: const ValueKey(
                            'close_halfscreen_outliner_btn',
                          ),
                          onTap: () {
                            _rebuild(() {
                              _isHalfScreenOutlinerOpen = false;
                            });
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 3,
                            ),
                            child: Text(
                              '✕',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              Offstage(
                offstage: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     const Text('OUTLINE'),
                    const Text('ACTIVE RELEASE'),
                    Text(
                      widget.workbench.activePhaseBadgeLabel,
                      key: const ValueKey('stage3_phase_badge'),
                    ),
                    InkWell(
                      key: const ValueKey('focus_mode_toggle_btn'),
                      onTap: () => widget.workbench.toggleFocusMode(),
                      child: const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Builder(
            builder: (context) {
              final pendingCount =
                  widget.workbench.pendingFeatureInboxItems.length;
              final scheduledCount =
                  widget.workbench.scheduledFeatureInboxItems.length;
              final totalInbox = pendingCount + scheduledCount;
              return InkWell(
                key: const ValueKey('open_feature_inbox_btn'),
                onTap: () => _showFeatureInboxModal(context),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: bgSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: pendingCount > 0 ? borderBright : borderSubtle,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          totalInbox > 0
                              ? '📥 Feature Inbox ($totalInbox)'
                              : '📥 Feature Inbox',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        pendingCount > 0
                            ? '$pendingCount TO TRIAGE ✦'
                            : '+ ADD IDEA ✦',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: pendingCount > 0
                              ? const Color(0xFF10B981)
                              : textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.workbench.backgroundStepSynthesisRemainingCount > 0)
          Padding(
            key: const ValueKey('outliner_background_synthesis_banner'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Row(
              children: [
                Text(
                  '⟳',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '✦ Generating engine steps (${widget.workbench.backgroundStepSynthesisRemainingCount} left)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (widget.workbench.releaseViewFilter == 'archived' &&
            archivedFeats.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ARCHIVED TESTBEDS (${archivedFeats.length})',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: textMuted,
                    ),
                  ),
                ),
                InkWell(
                  key: const ValueKey('return_from_archive_btn'),
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => widget.workbench.setReleaseViewFilter('active'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      '← Active',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final arch in archivedFeats)
            _buildFeatureRailItem(arch, activeVer: activeVer),
        ] else ...[
          Builder(
            builder: (context) {
              final releaseHasActiveFeats = beats.any(
                (b) => widget.workbench.featuresForBeat(b.id).any(
                      (f) => widget.workbench.isFeatureActiveInRelease(f),
                    ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int bIdx = 0; bIdx < beats.length; bIdx++)
                    Builder(
                      builder: (context) {
                        final beat = beats[bIdx];
                        final allBeatFeats =
                            widget.workbench.featuresForBeat(beat.id);
                        final showAllLiveFeatures =
                            widget.workbench.releaseViewFilter == 'all';
                        final beatFeats = (!showAllLiveFeatures &&
                                releaseHasActiveFeats)
                            ? allBeatFeats
                                .where(
                                  (f) => widget.workbench
                                      .isFeatureActiveInRelease(f),
                                )
                                .toList()
                            : allBeatFeats;
                        final isSynthesizingBeat = widget.workbench
                            .isSynthesizingBeatFeatures(beat.id);
                        if (beatFeats.isEmpty &&
                            allBeatFeats.isNotEmpty &&
                            !isSynthesizingBeat &&
                            _activeStage2InlineEditKey !=
                                'add_feat_${beat.id}') {
                          return const SizedBox.shrink();
                        }
                        final doneBeatCount = beatFeats
                            .where(
                              (f) =>
                                  widget.workbench.getDocumentProgress(f.id) >=
                                  100,
                            )
                            .length;
                        final allBeatDone = beatFeats.isNotEmpty &&
                            doneBeatCount == beatFeats.length;
                        final isBeatActive = beatFeats.any(
                          (f) => f.id == widget.workbench.selectedFeatureId,
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: InkWell(
                                key: ValueKey('rail_beat_${beat.id}'),
                                borderRadius: BorderRadius.circular(4),
                                onTap: () {
                                  if (beatFeats.isEmpty) return;
                                  final targetFeat = beatFeats.firstWhere(
                                    (f) =>
                                        widget.workbench
                                            .getDocumentProgress(f.id) <
                                        100,
                                    orElse: () => beatFeats.first,
                                  );
                                  _rebuild(() {
                                    _manualCheckpointFocusIndex = null;
                                  });
                                  widget.workbench
                                      .selectFeature(targetFeat.id);
                                },
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'E${(bIdx + 1).toString().padLeft(2, '0')} · ${_formatOutlineBeatDisplayTitle(beat.title).toUpperCase()}',
                                        maxLines: 2,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.8,
                                          height: 1.25,
                                          color: allBeatDone
                                              ? textMuted.withValues(alpha: 0.65)
                                              : (isBeatActive
                                                  ? textSecondary
                                                  : textMuted),
                                          decoration: allBeatDone
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                        ),
                                      ),
                                    ),
                                    if (isSynthesizingBeat) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '⟳',
                                        key: ValueKey(
                                          'rail_beat_synthesizing_${beat.id}',
                                        ),
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: textSecondary,
                                        ),
                                      ),
                                    ] else if (beatFeats.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '$doneBeatCount/${beatFeats.length}',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w500,
                                          color: textMuted,
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        'Queued',
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w500,
                                          color: textMuted,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 6),
                                    InkWell(
                                      key: ValueKey(
                                        'rail_add_feat_to_beat_${beat.id}',
                                      ),
                                      onTap: () => _startStage2InlineEdit(
                                        'add_feat_${beat.id}',
                                        '',
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                          vertical: 1,
                                        ),
                                        child: Text(
                                          '+',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: textSecondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_activeStage2InlineEditKey ==
                                'add_feat_${beat.id}')
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 2, 14, 6),
                                child: _buildStage2InlineEditor(
                                  editKey: 'add_feat_${beat.id}',
                                  inputKey: const ValueKey(
                                    'workbench_add_live_feature_input',
                                  ),
                                  saveBtnKey: const ValueKey(
                                    'confirm_workbench_add_live_feature_btn',
                                  ),
                                  hintText:
                                      'New feature (e.g. Shield Parry)...',
                                  onSave: (val) {
                                    _rebuild(() {
                                      _manualCheckpointFocusIndex = null;
                                      _manualCheckpointFocusFeatureId = null;
                                    });
                                    widget.workbench.addLiveFeatureToBeat(
                                      beat.id,
                                      val,
                                    );
                                  },
                                ),
                              ),
                            for (int fIdx = 0;
                                fIdx < beatFeats.length;
                                fIdx++)
                              _buildFeatureRailItem(
                                beatFeats[fIdx],
                                activeVer: activeVer,
                                beatTitle: beat.title,
                                beatIndex: bIdx,
                              ),
                          ],
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
          child: Builder(
            builder: (context) {
              final releaseHasActiveFeats = beats.any(
                (b) => widget.workbench.featuresForBeat(b.id).any(
                      (f) => widget.workbench.isFeatureActiveInRelease(f),
                    ),
              );
              int totalActiveFeats = 0;
              int verifiedFeats = 0;
              for (final b in beats) {
                for (final f in widget.workbench.featuresForBeat(b.id)) {
                  if (releaseHasActiveFeats &&
                      !widget.workbench.isFeatureActiveInRelease(f)) {
                    continue;
                  }
                  totalActiveFeats++;
                  if (widget.workbench.getDocumentProgress(f.id) >= 100) {
                    verifiedFeats++;
                  }
                }
              }
              return InkWell(
                key: const ValueKey('open_playtest_run_sheet_btn'),
                onTap: () => _showPlaytestRunSheetModal(context),
                borderRadius: BorderRadius.circular(5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '▶ Playtest Sheet ($verifiedFeats/$totalActiveFeats)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'GATE',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
          child: Builder(
            builder: (context) {
              final isRelComplete = widget.workbench.isActiveReleaseComplete;
              final nextVerLabel =
                  widget.workbench.nextProgressiveVersionLabel;
              return InkWell(
                key: const ValueKey('outliner_new_progressive_release_btn'),
                onTap: () => _showProgressiveNextReleaseModal(context),
                borderRadius: BorderRadius.circular(5),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          isRelComplete
                              ? '+ Plan Next Release ($nextVerLabel)'
                              : '🔒 $activeVer ($relProgress%) → $nextVerLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: isRelComplete
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isRelComplete
                                ? const Color(0xFF10B981)
                                : textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isRelComplete ? '✦ AI' : 'LOCKED',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: isRelComplete
                              ? const Color(0xFF10B981)
                              : textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: bgRecessed,
        border: Border(
          right: BorderSide(
            color: isOverlayDrawer ? borderBright : borderSubtle,
          ),
        ),
      ),
      child: SingleChildScrollView(child: content),
    );
  }

  Widget _buildFeatureRailItem(
    TierDocument feat, {
    required String activeVer,
    String? beatTitle,
    int beatIndex = 0,
  }) {
    final isSelected = widget.workbench.selectedFeatureId == feat.id;
    final progress = widget.workbench.getDocumentProgress(feat.id);
    final featRemMins = _computeFeatureRemainingMinutes(feat);
    final featRemLabel =
        TaskHowToBlueprint.formatRemainingHoursShort(featRemMins);
    final isDone = progress >= 100 || featRemMins <= 0;
    final isFocus = widget.workbench.focusMode;

    final shouldDim = isFocus && !isSelected;
    final displayTitle = _formatOutlineFeatureDisplayTitle(
      feat.title,
      beatTitle,
      beatIndex: beatIndex,
    );

    return Opacity(
      opacity: shouldDim ? 0.78 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: isSelected
              ? Border(
                  left: BorderSide(
                    color: textPrimary,
                    width: 2.5,
                  ),
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: ValueKey('rail_feat_${feat.id}'),
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                _rebuild(() {
                  _manualCheckpointFocusIndex = null;
                });
                widget.workbench.selectFeature(feat.id);
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  10,
                  7,
                  10,
                  7,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: InkWell(
                        key: ValueKey('outline_feat_chevron_${feat.id}'),
                        onTap: () {
                          _rebuild(() {
                            _manualCheckpointFocusIndex = null;
                          });
                          widget.workbench.selectFeature(feat.id);
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 14,
                          height: 18,
                          child: Center(
                            child: Text(
                              isDone ? '✓' : (isSelected ? '●' : '·'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected ? textPrimary : textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _activeStage2InlineEditKey ==
                              'rename_rail_feat_${feat.id}'
                          ? _buildStage2InlineEditor(
                              editKey: 'rename_rail_feat_${feat.id}',
                              inputKey: const ValueKey(
                                'workbench_rename_live_feature_input',
                              ),
                              saveBtnKey: const ValueKey(
                                'confirm_workbench_rename_live_feature_btn',
                              ),
                              hintText: 'Feature title...',
                              onSave: (val) => widget.workbench
                                  .renameLiveFeature(feat.id, val),
                              onDelete: () =>
                                  widget.workbench.removeLiveFeature(feat.id),
                              deleteBtnKey:
                                  ValueKey('rail_remove_feat_${feat.id}'),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayTitle,
                                  maxLines: 2,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    height: 1.25,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isDone
                                        ? textMuted.withValues(alpha: 0.6)
                                        : (isSelected
                                            ? textPrimary
                                            : textSecondary),
                                    decoration: isDone
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                  ),
                                ),
                                Builder(
                                  builder: (context) {
                                    final scheduledUpgrades = widget.workbench
                                        .scheduledInboxUpgradesForFeature(
                                      feat.id,
                                    );
                                    final isStableInAllView =
                                        widget.workbench.releaseViewFilter ==
                                                'all' &&
                                            !widget.workbench
                                                .isFeatureActiveInRelease(
                                              feat,
                                            ) &&
                                            feat.sections['lifecycle'] !=
                                                FeatureLifecycleStatus
                                                    .superseded.name;
                                    if (scheduledUpgrades.isEmpty &&
                                        !isStableInAllView) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        scheduledUpgrades.isNotEmpty
                                            ? '🗓 Queued for ${scheduledUpgrades.first.targetFuturePhase.shortName}: ${scheduledUpgrades.first.futureCheckpointTitle.isNotEmpty ? scheduledUpgrades.first.futureCheckpointTitle : scheduledUpgrades.first.checkpointTitle}'
                                            : 'STABLE ✓ (${feat.sections['originVersion'] ?? 'v0.1'})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: textMuted,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (displayTitle != feat.title)
                                  SizedBox(
                                    height: 1,
                                    child: Opacity(
                                      opacity: 0,
                                      child: Text(
                                        feat.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(width: 8),
                    if (feat.sections['lifecycle'] ==
                        FeatureLifecycleStatus.superseded.name) ...[
                      InkWell(
                        key: ValueKey('restore_archived_feat_${feat.id}'),
                        onTap: () =>
                            widget.workbench.toggleSupersedeFeature(feat.id),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          child: Text(
                            '↺ Restore',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ] else if (isSelected &&
                        !widget.workbench
                            .isSynthesizingFeatureSteps(feat.id) &&
                        _activeStage2InlineEditKey !=
                            'rename_rail_feat_${feat.id}') ...[
                      InkWell(
                        key: ValueKey('rail_rename_feat_${feat.id}'),
                        onTap: () => _startStage2InlineEdit(
                          'rename_rail_feat_${feat.id}',
                          feat.title,
                        ),
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 1,
                          ),
                          child: Text(
                            '✎',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      InkWell(
                        key: ValueKey('rail_supersede_feat_${feat.id}'),
                        onTap: () => widget.workbench.toggleSupersedeFeature(
                          feat.id,
                          pivotReason: 'Archived from Outliner in $activeVer',
                        ),
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 1,
                          ),
                          child: Text(
                            '⊗',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (widget.workbench.isSynthesizingFeatureSteps(feat.id)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 4),
                        child: Text(
                          '⟳',
                          key: ValueKey('rail_queued_badge_${feat.id}'),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: textMuted,
                          ),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        isDone ? 'DONE' : featRemLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.w500 : FontWeight.w400,
                          color: isSelected ? textSecondary : textMuted,
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
    );
  }

  /// Framed Step Timeline rendered inside the Work Area (Full-Width mode).
  /// Displays the active checkpoint's Task Groups and atomic Sub-Steps in sequential order.
  Widget _buildFlatFeatureStepTimeline({
    required TierDocument feat,
    required List<FeatureStateNode> states,
    required int checkpointIndex,
    required FeatureStateNode node,
    required List<TaskHowToBlueprint> howToBlueprints,
    required int selectedTaskIdx,
    required int activeSubStepIdx,
  }) {
    final engineHint = _engineHint;
    final unifiedTaskGroups = <({
      int cpIdx,
      FeatureStateNode cpNode,
      int tIdx,
      Subtask task,
      TaskHowToBlueprint bp,
    })>[];
    int totalDoneSteps = 0;
    int totalStepsCount = 0;

    final currentPhase = widget.workbench.currentPhase;
    final scheduledUpgrades =
        widget.workbench.scheduledInboxUpgradesForFeature(feat.id);

    for (int tIdx = 0; tIdx < node.checklist.length; tIdx++) {
      final bp = tIdx < howToBlueprints.length
          ? howToBlueprints[tIdx]
          : TaskHowToBlueprint.resolve(
              parentTask: node.checklist[tIdx],
              taskIndex: tIdx,
              checkpointNode: node,
              engineHint: engineHint,
              unrealCppMode: _unrealCppMode,
              phase: currentPhase,
            );
      totalStepsCount += bp.subSteps.length;
      totalDoneSteps += bp.subSteps.where((s) => s.subtask.completed).length;
      unifiedTaskGroups.add((
        cpIdx: checkpointIndex,
        cpNode: node,
        tIdx: tIdx,
        task: node.checklist[tIdx],
        bp: bp,
      ));
    }

    return Container(
      key: ValueKey('work_area_step_timeline_${node.id}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stage 1 Style Card Header Bar (01 STEPS + Done Counter + 1px Hairline)
          Container(
            padding: const EdgeInsets.only(bottom: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '01',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'STEPS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                            color: textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$totalDoneSteps/$totalStepsCount Done',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (states.length == 1 && scheduledUpgrades.isEmpty)
            Offstage(
              offstage: true,
              child: InkWell(
                key: ValueKey('outline_cp_${feat.id}_0'),
                onTap: () {
                  _rebuild(() {
                    _manualCheckpointFocusIndex = 0;
                    _manualCheckpointFocusFeatureId = feat.id;
                  });
                },
                child: const SizedBox.shrink(),
              ),
            )
          else if (states.length > 1 || scheduledUpgrades.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bgRecessed,
                border: Border(
                  bottom: BorderSide(color: borderSubtle),
                ),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (int cpIdx = 0; cpIdx < states.length; cpIdx++)
                    InkWell(
                      key: ValueKey('outline_cp_${feat.id}_$cpIdx'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        _rebuild(() {
                          _manualCheckpointFocusIndex = cpIdx;
                          _manualCheckpointFocusFeatureId = feat.id;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: cpIdx == checkpointIndex
                              ? Border(
                                  bottom: BorderSide(
                                    color: textPrimary,
                                    width: 2,
                                  ),
                                )
                              : null,
                        ),
                        child: Text(
                          'CP${cpIdx + 1} · ${states[cpIdx].releaseVersion}${states[cpIdx].isCompleted ? ' ✓' : ''}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: cpIdx == checkpointIndex
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: cpIdx == checkpointIndex
                                ? textPrimary
                                : textMuted,
                          ),
                        ),
                      ),
                    ),
                  for (final upg in scheduledUpgrades)
                    InkWell(
                      key: ValueKey(
                        'outline_scheduled_inbox_chip_${feat.id}_${upg.id}',
                      ),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _showFeatureInboxModal(context),
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
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: accentEmerald,
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
                for (int gIdx = 0; gIdx < unifiedTaskGroups.length; gIdx++)
                  Builder(
                    builder: (context) {
                      final grp = unifiedTaskGroups[gIdx];
                      final cpIdx = grp.cpIdx;
                      final cpNode = grp.cpNode;
                      final tIdx = grp.tIdx;
                      final bp = grp.bp;
                      final task = grp.task;
                      final globalNumLabel =
                          (tIdx + 1).toString().padLeft(2, '0');
                      final isFixTask = task.text.trim().startsWith('[FIX]');
                      final isTaskActive =
                          cpIdx == checkpointIndex && tIdx == selectedTaskIdx;
                      final doneSubCount = bp.subSteps
                          .where((s) => s.subtask.completed)
                          .length;
                      final totalSubCount = bp.subSteps.length;
                      final groupTitle = bp.shortTaskTitle;

                      return Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: isTaskActive ? 11 : 9,
                        ),
                        decoration: BoxDecoration(
                          border: gIdx == 0
                              ? null
                              : Border(
                                  top: BorderSide(color: borderSubtle),
                                ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Clean Task Group Overline (or Inline Editor when editing task title)
                            if (_activeStage2InlineEditKey ==
                                'edit_task_${cpNode.id}_$tIdx')
                              _buildStage2InlineEditor(
                                editKey: 'edit_task_${cpNode.id}_$tIdx',
                                inputKey: const ValueKey(
                                  'edit_stage3_task_title_input',
                                ),
                                saveBtnKey: const ValueKey(
                                  'save_stage3_task_title_btn',
                                ),
                                deleteBtnKey: const ValueKey(
                                  'delete_stage3_task_btn',
                                ),
                                hintText: 'Edit task title...',
                                onSave: (val) {
                                  task.text = val;
                                  TaskHowToBlueprint.clearCache();
                                  widget.workbench.updateFeatureStates(
                                    feat.id,
                                    states,
                                  );
                                },
                                onDelete: cpNode.checklist.length > 1
                                    ? () {
                                        cpNode.checklist.removeAt(tIdx);
                                        TaskHowToBlueprint.clearCache();
                                        widget.workbench.updateFeatureStates(
                                          feat.id,
                                          states,
                                        );
                                        _rebuild(() {
                                          final nextIdx = cpNode.checklist.isEmpty
                                              ? 0
                                              : tIdx.clamp(
                                                  0,
                                                  cpNode.checklist.length - 1,
                                                );
                                          _selectedTaskIndexByCheckpoint[
                                              cpNode.id] = nextIdx;
                                          _selectedSubStepIndexByTask[
                                              '${cpNode.id}_$nextIdx'] = 0;
                                        });
                                      }
                                    : null,
                              )
                            else
                              InkWell(
                                key: ValueKey('outline_task_${cpNode.id}_$tIdx'),
                                onTap: () {
                                  _rebuild(() {
                                    _manualCheckpointFocusIndex = cpIdx;
                                    _manualCheckpointFocusFeatureId = feat.id;
                                    _selectedTaskIndexByCheckpoint[cpNode.id] =
                                        tIdx;
                                  });
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: RichText(
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text:
                                                    '${isTaskActive ? '▾' : '▸'} $globalNumLabel  ',
                                                style:
                                                    GoogleFonts.jetBrainsMono(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: isFixTask
                                                      ? accentCrimson
                                                      : (isTaskActive
                                                          ? textPrimary
                                                          : textMuted),
                                                ),
                                              ),
                                              TextSpan(
                                                text: groupTitle,
                                                style: GoogleFonts.inter(
                                                  fontSize: 12.5,
                                                  fontWeight: isTaskActive
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                  color: isFixTask
                                                      ? accentCrimson
                                                      : (isTaskActive
                                                          ? textPrimary
                                                          : textSecondary),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        key: ValueKey(
                                          'edit_active_task_title_btn_${cpNode.id}_$tIdx',
                                        ),
                                        onTap: () => _startStage2InlineEdit(
                                          'edit_task_${cpNode.id}_$tIdx',
                                          task.text,
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                            vertical: 1,
                                          ),
                                          child: Icon(
                                            Icons.edit_outlined,
                                            size: 11,
                                            color: isTaskActive
                                                ? textSecondary
                                                : textMuted,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      InkWell(
                                        key: ValueKey(
                                          'complete_task_group_${cpNode.id}_$tIdx',
                                        ),
                                        onTap: () => _toggleTaskGroupCompletion(
                                          feat,
                                          states,
                                          cpNode,
                                          tIdx,
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                            vertical: 1,
                                          ),
                                          child: Text(
                                            task.completed
                                                ? '✓ $doneSubCount/$totalSubCount'
                                                : '$doneSubCount/$totalSubCount',
                                            style: GoogleFonts.jetBrainsMono(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: isTaskActive
                                                  ? textSecondary
                                                  : textMuted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (isTaskActive) ...[
                              const SizedBox(height: 6),
                              // Continuous 1px vertical track line with crisp 1-line Steps
                              Container(
                                margin: const EdgeInsets.only(left: 7),
                                padding: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: borderSubtle,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (int sIdx = 0;
                                        sIdx < bp.subSteps.length;
                                        sIdx++)
                                      Builder(
                                        builder: (context) {
                                          final stepItem = bp.subSteps[sIdx];
                                          final isStepActive = isTaskActive &&
                                              sIdx == activeSubStepIdx;
                                          final isStepDone =
                                              stepItem.subtask.completed;
                                          return Opacity(
                                            opacity: isStepActive
                                                ? 1.0
                                                : (isStepDone ? 0.55 : 0.78),
                                            child: InkWell(
                                              key: ValueKey(
                                                'task_sheet_step_row_${cpNode.id}_${tIdx}_$sIdx',
                                              ),
                                              onTap: () {
                                                _rebuild(() {
                                                  _manualCheckpointFocusIndex =
                                                      cpIdx;
                                                  _manualCheckpointFocusFeatureId =
                                                      feat.id;
                                                  _selectedTaskIndexByCheckpoint[
                                                      cpNode.id] = tIdx;
                                                  _selectedSubStepIndexByTask[
                                                      '${cpNode.id}_$tIdx'] = sIdx;
                                                });
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                  bottom: 2,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 7,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.transparent,
                                                  border: isStepActive
                                                      ? Border(
                                                          left: BorderSide(
                                                            color: textPrimary,
                                                            width: 2.5,
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    SizedBox(
                                                      width: 18,
                                                      child: Text(
                                                        isStepDone &&
                                                                !isStepActive
                                                            ? '✓'
                                                            : (sIdx + 1)
                                                                .toString()
                                                                .padLeft(
                                                                  2,
                                                                  '0',
                                                                ),
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              isStepActive
                                                                  ? FontWeight
                                                                      .w600
                                                                  : FontWeight
                                                                      .w400,
                                                          color: isStepActive
                                                              ? textPrimary
                                                              : textMuted,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        stepItem.shortTitle,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style:
                                                            GoogleFonts.inter(
                                                          fontSize: 12,
                                                          height: 1.25,
                                                          fontWeight:
                                                              isStepActive
                                                                  ? FontWeight
                                                                      .w600
                                                                  : FontWeight
                                                                      .w400,
                                                          color: isStepActive
                                                              ? textPrimary
                                                              : textSecondary,
                                                          decoration: isStepDone &&
                                                                  !isStepActive
                                                              ? TextDecoration
                                                                  .lineThrough
                                                              : TextDecoration
                                                                  .none,
                                                        ),
                                                      ),
                                                    ),
                                                    if (!isStepDone) ...[
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        stepItem.etaLabel,
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 9.5,
                                                          fontWeight:
                                                              isStepActive
                                                                  ? FontWeight
                                                                      .w500
                                                                  : FontWeight
                                                                      .w400,
                                                          color: isStepActive
                                                              ? textSecondary
                                                              : textMuted,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ] else
                              for (int sIdx = 0;
                                  sIdx < bp.subSteps.length;
                                  sIdx++)
                                Offstage(
                                  offstage: true,
                                  child: InkWell(
                                    key: ValueKey(
                                      'task_sheet_step_row_${cpNode.id}_${tIdx}_$sIdx',
                                    ),
                                    onTap: () {
                                      _rebuild(() {
                                        _manualCheckpointFocusIndex = cpIdx;
                                        _manualCheckpointFocusFeatureId =
                                            feat.id;
                                        _selectedTaskIndexByCheckpoint[
                                            cpNode.id] = tIdx;
                                        _selectedSubStepIndexByTask[
                                            '${cpNode.id}_$tIdx'] = sIdx;
                                      });
                                    },
                                    child: const SizedBox.shrink(),
                                  ),
                                ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 12),
                if (_activeStage2InlineEditKey == 'add_task_${node.id}')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: _buildStage2InlineEditor(
                      editKey: 'add_task_${node.id}',
                      inputKey: const ValueKey('add_stage3_task_title_input'),
                      saveBtnKey: const ValueKey('confirm_add_stage3_task_btn'),
                      hintText: 'Add build task (e.g. Wall-jump impulse (2h))...',
                      onSave: (val) => _commitInlineAddBuildTask(
                        feat,
                        states,
                        checkpointIndex,
                        val,
                      ),
                    ),
                  )
                else
                  InkWell(
                    key: ValueKey('outline_add_task_btn_${node.id}'),
                    onTap: () => _startStage2InlineEdit(
                      'add_task_${node.id}',
                      '',
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                      child: Text(
                        '+ Add Build Task...',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFeatureMainCanvas(
    TierDocument rel, {
    bool isHalfScreenOverlayMode = false,
  }) {
    final feat = widget.workbench.selectedFeature;
    if (feat == null) {
      return Center(
        child: Text(
          'Select a Feature from the left rail.',
          style: GoogleFonts.inter(color: textMuted),
        ),
      );
    }

    final states = FeatureStateNode.getStatesForDocument(feat);
    final progress = widget.workbench.getDocumentProgress(feat.id).toDouble();
    final isDone = progress >= 100;
    final nextFeat = widget.workbench.nextIncompleteFeature;

    final activeVer = widget.workbench.activeReleaseVersionTag;
    int activeFocusIndex = -1;
    // 1. Prioritize incomplete (or awaiting playtest) checkpoints belonging to the active release
    for (int i = 0; i < states.length; i++) {
      final s = states[i];
      if (s.releaseVersion != activeVer) continue;
      final awaitingPlaytest = _awaitingPlaytestVerification.contains(s.id);
      if (!s.isCompleted || awaitingPlaytest) {
        activeFocusIndex = i;
        break;
      }
    }
    // 2. Otherwise prefer the last checkpoint belonging to the active release
    if (activeFocusIndex == -1) {
      activeFocusIndex =
          states.lastIndexWhere((s) => s.releaseVersion == activeVer);
    }
    // 3. Fall back to any incomplete checkpoint or the last checkpoint
    if (activeFocusIndex == -1) {
      for (int i = 0; i < states.length; i++) {
        final s = states[i];
        final awaitingPlaytest = _awaitingPlaytestVerification.contains(s.id);
        if (!s.isCompleted || awaitingPlaytest) {
          activeFocusIndex = i;
          break;
        }
      }
    }
    if (activeFocusIndex == -1 && states.isNotEmpty) {
      activeFocusIndex = states.length - 1;
    }
    final effectiveFocusIndex = (_manualCheckpointFocusFeatureId == feat.id &&
            _manualCheckpointFocusIndex != null &&
            _manualCheckpointFocusIndex! >= 0 &&
            _manualCheckpointFocusIndex! < states.length)
        ? _manualCheckpointFocusIndex!
        : activeFocusIndex;

    Widget buildBody() {
      final activeFeatureContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.workbench.isActiveReleaseComplete) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: _buildReleaseShippedBanner(rel),
            ),
          ] else if (isDone && nextFeat != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: _buildNextFeatureAdvanceBanner(feat, nextFeat),
            ),
          ],
          for (int i = 0; i < states.length; i++)
            if (!widget.workbench.focusMode ||
                i == effectiveFocusIndex ||
                states.length <= 1)
              _buildCheckpointCard(
                feat,
                states,
                i,
                activeFocusIndex: effectiveFocusIndex,
                isHalfScreenOverlayMode: isHalfScreenOverlayMode,
              ),
        ],
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('stage3_active_feature_sheet'),
            child: activeFeatureContent,
          ),
        ],
      );
    }

    return Container(
      color: bgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, viewportConstraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: viewportConstraints.maxWidth,
                    ),
                    child: buildBody(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextFeatureAdvanceBanner(
    TierDocument completedFeat,
    TierDocument nextFeat,
  ) {
    final completedBeat = completedFeat.parentId != null
        ? widget.workbench.documents[completedFeat.parentId!]
        : null;
    final nextBeat = nextFeat.parentId != null
        ? widget.workbench.documents[nextFeat.parentId!]
        : null;
    final completedTitle = _formatOutlineFeatureDisplayTitle(
      completedFeat.title,
      completedBeat?.title,
    );
    final nextTitle = _formatOutlineFeatureDisplayTitle(
      nextFeat.title,
      nextBeat?.title,
    );

    return Container(
      key: const ValueKey('next_feature_advance_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: textPrimary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$completedTitle is 100% VERIFIED ✓! Ready for the next feature in your loop?',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            key: const ValueKey('continue_to_next_feature_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: const Color(0xFF06281E),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => widget.workbench.selectFeature(nextFeat.id),
            icon: const Icon(Icons.arrow_forward_rounded, size: 15),
            label: Text(
              'Continue to $nextTitle →',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseShippedBanner(TierDocument rel) {
    final nextVer = widget.workbench.nextProgressiveVersionLabel;
    return Container(
      key: const ValueKey('release_complete_next_release_banner'),
      child: Container(
        key: const ValueKey('release_complete_banner'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderSubtle),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.verified_rounded, color: textPrimary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'All Features in ${rel.title} are 100% Complete ✓!',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
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
                OutlinedButton.icon(
                  key: const ValueKey('release_shipped_summary_btn'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textSecondary,
                    side: BorderSide(color: borderSubtle),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: () => _showReleaseShippedSummaryModal(context, rel),
                  icon: const Icon(Icons.emoji_events_outlined, size: 14),
                  label: Text(
                    'Release Summary',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('banner_launch_next_release_btn'),
                  child: ElevatedButton.icon(
                    key: const ValueKey('ship_and_plan_next_release_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: const Color(0xFF06281E),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => _showProgressiveNextReleaseModal(context),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 14),
                    label: Text(
                      '+ New Release ($nextVer) ✦',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}
