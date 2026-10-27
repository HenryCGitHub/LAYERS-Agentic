part of 'release_workbench_screen.dart';

extension _WorkbenchOutlinerAndShellExt on _ReleaseWorkbenchScreenState {
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
                        } else if (value.startsWith('rel:')) {
                          final targetId = value.substring(4);
                          final targetDoc = widget.workbench.documents[targetId];
                          if (targetDoc != null &&
                              targetDoc.childrenIds.isEmpty &&
                              targetId != rel.id) {
                            _showProgressiveNextReleaseModal(context);
                          } else {
                            widget.workbench.selectActiveRelease(targetId);
                          }
                        } else {
                          widget.workbench.setReleaseViewFilter(value);
                        }
                      },
                      itemBuilder: (context) {
                        final queuedDeferredCount = widget.workbench.releaseBlueprint?.beats
                                .fold<int>(0, (sum, b) => sum + b.deferredFeatures.length) ??
                            0;
                        return [
                          PopupMenuItem<String>(
                            enabled: false,
                            height: 24,
                            child: Text(
                              'RELEASES · SWITCH OR PLAN',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: textMuted,
                              ),
                            ),
                          ),
                          for (int rIdx = 0; rIdx < releases.length; rIdx++)
                            PopupMenuItem<String>(
                              value: 'rel:${releases[rIdx].id}',
                              child: Builder(
                                builder: (context) {
                                  final r = releases[rIdx];
                                  final isCurrent = r.id == rel.id;
                                  final isBuilt = r.childrenIds.isNotEmpty;
                                  final rVer =
                                      widget.workbench.releaseVersionTagFor(r);
                                  final rScopeLabel =
                                      widget.workbench.releaseConciseLabel(r);
                                  final rProg = widget.workbench.getDocumentProgress(r.id);
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? accentCyan.withValues(alpha: 0.08)
                                          : Colors.transparent,
                                      border: Border(
                                        left: BorderSide(
                                          color: isCurrent
                                              ? accentCyan
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    isCurrent
                                                        ? '● '
                                                        : (isBuilt ? '✓ ' : '◌ '),
                                                    style: GoogleFonts.jetBrainsMono(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w800,
                                                      color: isCurrent
                                                          ? accentCyan
                                                          : (isBuilt
                                                              ? accentEmerald
                                                              : accentAmber),
                                                    ),
                                                  ),
                                                  Text(
                                                    '$rVer ',
                                                    style: GoogleFonts.jetBrainsMono(
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.w800,
                                                      color: isCurrent
                                                          ? accentCyan
                                                          : textPrimary,
                                                    ),
                                                  ),
                                                  Flexible(
                                                    child: Text(
                                                      rScopeLabel,
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11.5,
                                                        fontWeight: isCurrent
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                        color: isCurrent
                                                            ? textPrimary
                                                            : textSecondary,
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
                                                  fontWeight: FontWeight.w700,
                                                  color: accentEmerald,
                                                ),
                                              )
                                            else if (isBuilt)
                                              Text(
                                                '$rProg%',
                                                style: GoogleFonts.jetBrainsMono(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: rProg >= 100
                                                      ? accentEmerald
                                                      : textMuted,
                                                ),
                                              )
                                            else
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: accentAmber.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: accentAmber.withValues(alpha: 0.35),
                                                  ),
                                                ),
                                                child: Text(
                                                  'Build Release →',
                                                  style: GoogleFonts.jetBrainsMono(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: accentAmber,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (!isBuilt && queuedDeferredCount > 0) ...[
                                          const SizedBox(height: 3),
                                          Padding(
                                            padding: const EdgeInsets.only(left: 14),
                                            child: Text(
                                              '↪ $queuedDeferredCount Features queued from $activeVer',
                                              style: GoogleFonts.jetBrainsMono(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w600,
                                                color: accentAmber,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          if (archivedFeats.isNotEmpty) ...[
                            const PopupMenuDivider(),
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
                          ],
                          const PopupMenuDivider(),
                          PopupMenuItem<String>(
                            enabled: false,
                            height: 24,
                            child: Text(
                              'PROGRESSIVE AI RELEASES',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: textMuted,
                              ),
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: '__progressive_release__',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '+ New Progressive Release (${widget.workbench.nextProgressiveVersionLabel})',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: accentEmerald,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'AI Co-Pilot ✦',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: accentEmerald,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ];
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 3,
                        ),
                        child: RichText(
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
                                  fontWeight: FontWeight.w800,
                                  color: accentCyan,
                                ),
                              ),
                              TextSpan(
                                text:
                                    '${widget.workbench.releaseConciseLabel(rel)} ▾',
                              ),
                            ],
                          ),
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
                            fontWeight: FontWeight.w700,
                            color: isReleaseDone ? accentEmerald : textPrimary,
                          ),
                          children: [
                            TextSpan(text: '$releaseRemHoursStr Left '),
                            TextSpan(
                              text: '$relProgress%',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: accentEmerald,
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
                      fontWeight: FontWeight.w800,
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
                        fontWeight: FontWeight.w700,
                        color: accentEmerald,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final arch in archivedFeats)
            _buildFeatureRailItem(arch, activeVer: activeVer),
        ] else
          for (int bIdx = 0; bIdx < beats.length; bIdx++) ...[
            Builder(
              builder: (context) {
                final beat = beats[bIdx];
                final beatFeats = widget.workbench.featuresForBeat(beat.id);
                final doneBeatCount = beatFeats
                    .where((f) => widget.workbench.getDocumentProgress(f.id) >= 100)
                    .length;
                final allBeatDone = beatFeats.isNotEmpty && doneBeatCount == beatFeats.length;
                final isBeatActive = beatFeats.any(
                  (f) => f.id == widget.workbench.selectedFeatureId,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: InkWell(
                        key: ValueKey('rail_beat_${beat.id}'),
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          if (beatFeats.isEmpty) return;
                          final targetFeat = beatFeats.firstWhere(
                            (f) => widget.workbench.getDocumentProgress(f.id) < 100,
                            orElse: () => beatFeats.first,
                          );
                          _rebuild(() {
                            _manualCheckpointFocusIndex = null;
                          });
                          widget.workbench.selectFeature(targetFeat.id);
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'E${(bIdx + 1).toString().padLeft(2, '0')} · ${_formatOutlineBeatDisplayTitle(beat.title).toUpperCase()}',
                                maxLines: 2,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  height: 1.25,
                                  color: allBeatDone
                                      ? accentEmerald.withValues(alpha: 0.75)
                                      : (isBeatActive ? textSecondary : textMuted),
                                  decoration: allBeatDone
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                ),
                              ),
                            ),
                              if (beatFeats.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Builder(
                                  builder: (context) {
                                    final allBeatStable = beatFeats.every(
                                      (f) => f.sections['lifecycle'] == 'stable',
                                    );
                                    return Text(
                                      allBeatStable
                                          ? 'STABLE ✓'
                                          : '$doneBeatCount/${beatFeats.length}',
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: allBeatDone || allBeatStable
                                            ? accentEmerald
                                            : textMuted,
                                      ),
                                    );
                                  },
                                ),
                              ],
                              const SizedBox(width: 6),
                              InkWell(
                                key: ValueKey('rail_add_feat_to_beat_${beat.id}'),
                                onTap: () => _showAddLiveFeatureDialog(beat),
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
                                      fontWeight: FontWeight.w800,
                                      color: accentCyan,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                        ),
                      ),
                    ),
                    for (int fIdx = 0; fIdx < beatFeats.length; fIdx++)
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
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
          child: Builder(
            builder: (context) {
              int totalActiveFeats = 0;
              int verifiedFeats = 0;
              for (final b in beats) {
                for (final f in widget.workbench.featuresForBeat(b.id)) {
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
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: accentCyan,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'GATE',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: verifiedFeats == totalActiveFeats &&
                                  totalActiveFeats > 0
                              ? accentEmerald
                              : accentAmber,
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
          child: InkWell(
            key: const ValueKey('outliner_new_progressive_release_btn'),
            onTap: () => _showProgressiveNextReleaseModal(context),
            borderRadius: BorderRadius.circular(5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      '+ New Release (${widget.workbench.nextProgressiveVersionLabel})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: accentEmerald,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '✦ AI',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: accentCyan,
                    ),
                  ),
                ],
              ),
            ),
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
      opacity: shouldDim ? 0.45 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.035)
                  : bgSurface)
              : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: ValueKey('rail_feat_${feat.id}'),
              onTap: () {
                _rebuild(() {
                  _manualCheckpointFocusIndex = null;
                });
                widget.workbench.selectFeature(feat.id);
              },
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  isSelected ? 13 : 16,
                  8,
                  16,
                  8,
                ),
                decoration: BoxDecoration(
                  border: isSelected
                      ? Border(
                          left: BorderSide(
                            color: isDone ? accentEmerald : accentCyan,
                            width: 3,
                          ),
                        )
                      : null,
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
                                isDone
                                    ? '✓'
                                    : (isSelected ? '●' : '·'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: isDone
                                    ? accentEmerald
                                    : (isSelected ? accentCyan : textMuted),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            maxLines: 2,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              height: 1.25,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isDone
                                  ? textMuted.withValues(alpha: 0.6)
                                  : (isSelected ? textPrimary : textSecondary),
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
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
                    if (isSelected) ...[
                      InkWell(
                        key: ValueKey('rail_rename_feat_${feat.id}'),
                        onTap: () => _showRenameLiveFeatureDialog(feat),
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
                        key: ValueKey('rail_remove_feat_${feat.id}'),
                        onTap: () => widget.workbench.removeLiveFeature(feat.id),
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 1,
                          ),
                          child: Text(
                            '×',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        isDone ? 'DONE' : featRemLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: isSelected || isDone
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isDone
                              ? accentEmerald
                              : (isSelected ? accentCyan : textMuted),
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

    for (int tIdx = 0; tIdx < node.checklist.length; tIdx++) {
      final bp = tIdx < howToBlueprints.length
          ? howToBlueprints[tIdx]
          : TaskHowToBlueprint.resolve(
              parentTask: node.checklist[tIdx],
              taskIndex: tIdx,
              checkpointNode: node,
              engineHint: engineHint,
              unrealCppMode: _unrealCppMode,
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
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Framed STEPS Card Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: bgSurfaceHover,
              border: Border(
                bottom: BorderSide(color: borderSubtle),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'STEPS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$totalDoneSteps/$totalStepsCount DONE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: totalDoneSteps > 0 ? accentEmerald : textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (states.length == 1)
            Offstage(
              offstage: true,
              child: InkWell(
                key: ValueKey('outline_cp_${feat.id}_0'),
                onTap: () {
                  _rebuild(() {
                    _manualCheckpointFocusIndex = 0;
                  });
                },
                child: const SizedBox.shrink(),
              ),
            )
          else if (states.length > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bgRecessed,
                border: Border(
                  bottom: BorderSide(color: borderSubtle),
                ),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (int cpIdx = 0; cpIdx < states.length; cpIdx++)
                    InkWell(
                      key: ValueKey('outline_cp_${feat.id}_$cpIdx'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        _rebuild(() {
                          _manualCheckpointFocusIndex = cpIdx;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cpIdx == checkpointIndex
                              ? accentCyan.withValues(alpha: 0.14)
                              : bgSurface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: cpIdx == checkpointIndex
                                ? accentCyan.withValues(alpha: 0.55)
                                : borderSubtle,
                          ),
                        ),
                        child: Text(
                          'CP${cpIdx + 1} · ${states[cpIdx].releaseVersion}${states[cpIdx].isCompleted ? ' ✓' : ''}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: cpIdx == checkpointIndex
                                ? accentCyan
                                : (states[cpIdx].isCompleted
                                    ? accentEmerald
                                    : textSecondary),
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
                      final groupTitle = bp.shortTaskTitle.toUpperCase();

                      return Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: isTaskActive ? 12 : 10,
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
                            // Clean Task Group Overline (separated by card divider, no nested inner box)
                            InkWell(
                              key: ValueKey('outline_task_${cpNode.id}_$tIdx'),
                              onTap: () {
                                _rebuild(() {
                                  _manualCheckpointFocusIndex = cpIdx;
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
                                      child: Text(
                                        '${isTaskActive ? '▾' : '▸'} $globalNumLabel · $groupTitle',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                          color: task.completed
                                              ? accentEmerald.withValues(
                                                  alpha: 0.8,
                                                )
                                              : (isFixTask
                                                  ? accentCrimson
                                                  : (isTaskActive
                                                      ? accentCyan
                                                      : textSecondary)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      key: ValueKey(
                                        'edit_active_task_title_btn_${cpNode.id}_$tIdx',
                                      ),
                                      onTap: () => _showEditBuildTaskTitleDialog(
                                        feat,
                                        states,
                                        task,
                                        cpNode: cpNode,
                                        taskIndex: tIdx,
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
                                              ? accentCyan
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
                                            fontWeight: FontWeight.w700,
                                            color: task.completed
                                                ? accentEmerald.withValues(
                                                    alpha: 0.85,
                                                  )
                                                : (isTaskActive
                                                    ? accentCyan
                                                    : textMuted),
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
                                                  _selectedTaskIndexByCheckpoint[
                                                      cpNode.id] = tIdx;
                                                  _selectedSubStepIndexByTask[
                                                      '${cpNode.id}_$tIdx'] = sIdx;
                                                });
                                              },
                                              borderRadius:
                                                  const BorderRadius.only(
                                                topRight: Radius.circular(6),
                                                bottomRight: Radius.circular(6),
                                              ),
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
                                                  color: isStepActive
                                                      ? accentCyan.withValues(
                                                          alpha: 0.14,
                                                        )
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                    topRight:
                                                        Radius.circular(6),
                                                    bottomRight:
                                                        Radius.circular(6),
                                                  ),
                                                  border: Border(
                                                    left: BorderSide(
                                                      color: isStepActive
                                                          ? accentCyan
                                                          : Colors.transparent,
                                                      width: 2.5,
                                                    ),
                                                  ),
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
                                                            : (isStepActive
                                                                ? '●'
                                                                : (sIdx + 1)
                                                                    .toString()
                                                                    .padLeft(
                                                                      2,
                                                                      '0',
                                                                    )),
                                                        style: GoogleFonts
                                                            .jetBrainsMono(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: isStepActive
                                                              ? accentCyan
                                                              : (isStepDone
                                                                  ? accentEmerald
                                                                  : textMuted),
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
                                                                      .w700
                                                                  : FontWeight
                                                                      .w500,
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
                                                                      .w700
                                                                  : FontWeight
                                                                      .w500,
                                                          color: isStepActive
                                                              ? accentCyan
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
                InkWell(
                  key: ValueKey('outline_add_task_btn_${node.id}'),
                  onTap: () => _showAddBuildTaskDialog(
                    feat,
                    states,
                    checkpointIndex,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                    child: Text(
                      '+ Add Build Task...',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: accentCyan.withValues(alpha: 0.85),
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
      if (activeFocusIndex == -1 && (!s.isCompleted || awaitingPlaytest)) {
        activeFocusIndex = i;
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
        if (activeFocusIndex == -1 && (!s.isCompleted || awaitingPlaytest)) {
          activeFocusIndex = i;
        }
      }
    }
    if (activeFocusIndex == -1 && states.isNotEmpty) {
      activeFocusIndex = states.length - 1;
    }
    final effectiveFocusIndex = (_manualCheckpointFocusIndex != null &&
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
        border: Border.all(color: borderBright),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: accentEmerald,
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
              backgroundColor: focalAccent,
              foregroundColor: focalAccentFg,
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
                fontWeight: FontWeight.w800,
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
          color: accentEmerald.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accentEmerald.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.verified_rounded, color: accentEmerald, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'All Features in ${rel.title} are 100% Complete ✓!',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
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
                    foregroundColor: accentEmerald,
                    side: BorderSide(color: accentEmerald.withValues(alpha: 0.5)),
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('banner_launch_next_release_btn'),
                  child: ElevatedButton.icon(
                    key: const ValueKey('ship_and_plan_next_release_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: focalAccent,
                      foregroundColor: focalAccentFg,
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
                        fontWeight: FontWeight.w800,
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
