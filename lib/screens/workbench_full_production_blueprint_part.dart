part of 'release_workbench_screen.dart';

/// Act 2 · Full Production Blueprint modal (6 sections, Stage-1-style option cards).
/// Opens after the Vertical Slice is complete; approving builds the `v0.N` Full-Game Skeleton.
extension _WorkbenchFullProductionBlueprintExt on _ReleaseWorkbenchScreenState {
  static const List<
      ({
        String num,
        String title,
        String key,
        bool isList,
        String hint,
      })> _fpSections = [
    (
      num: '01',
      title: 'v1.0 Goal',
      key: 'goal',
      isList: false,
      hint: '[2–4 Word Payoff] — [Full-game scope]',
    ),
    (
      num: '02',
      title: 'Content & World Scale',
      key: 'contentScale',
      isList: true,
      hint: '1 per line (e.g. 3 Biomes, 6 Enemy Types, 3 Bosses)',
    ),
    (
      num: '03',
      title: 'Full-Game Loop',
      key: 'fullGameLoop',
      isList: true,
      hint: '1 beat per line (launch → progression → finale → save)',
    ),
    (
      num: '04',
      title: 'Promoted Systems',
      key: 'promotedSystems',
      isList: true,
      hint: '1 per line (e.g. Save & Load, Title Menu)',
    ),
    (
      num: '05',
      title: 'Permanent Cuts',
      key: 'permanentCuts',
      isList: true,
      hint: '1 per line (e.g. No Online Co-Op)',
    ),
    (
      num: '06',
      title: 'v1.0 Done When',
      key: 'doneWhen',
      isList: false,
      hint: '[Player Action] → [Observable Result]',
    ),
  ];

  String _fpSectionText(FullProductionBlueprint bp, String key) =>
      switch (key) {
        'goal' => bp.goal,
        'contentScale' => bp.contentScale.join('\n'),
        'fullGameLoop' => bp.fullGameLoop.join('\n'),
        'promotedSystems' => bp.promotedSystems.join('\n'),
        'permanentCuts' => bp.permanentCuts.join('\n'),
        'doneWhen' => bp.doneWhen,
        _ => '',
      };

  void _applyFpSectionText(FullProductionBlueprint bp, String key, String raw) {
    List<String> lines() => raw
        .split(RegExp(r'\n|\s\|\s'))
        .map((l) => l.replaceFirst(RegExp(r'^[•\-\*\s]+'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    switch (key) {
      case 'goal':
        bp.goal = raw.trim();
      case 'contentScale':
        bp.contentScale = lines();
      case 'fullGameLoop':
        bp.fullGameLoop = lines();
      case 'promotedSystems':
        bp.promotedSystems = lines();
      case 'permanentCuts':
        bp.permanentCuts = lines();
      case 'doneWhen':
        bp.doneWhen = raw.trim();
    }
  }

  Future<void> _showFullProductionBlueprintModal(
    BuildContext context, {
    bool readOnly = false,
  }) async {
    final wb = widget.workbench;
    FullProductionBlueprint? draft = wb.fullProductionBlueprint;
    bool isLoading = draft == null && !readOnly;
    bool isBuilding = false;
    bool dialogOpen = true;
    StateSetter? modalSetState;
    final controllers = <String, TextEditingController>{
      for (final s in _fpSections) s.key: TextEditingController(),
    };
    void syncControllers() {
      final bp = draft;
      if (bp == null) return;
      for (final s in _fpSections) {
        controllers[s.key]!.text = _fpSectionText(bp, s.key);
      }
    }

    syncControllers();
    if (isLoading) {
      wb.draftFullProductionBlueprint().then((drafted) {
        draft = drafted ?? FullProductionBlueprint();
        isLoading = false;
        syncControllers();
        if (dialogOpen) modalSetState?.call(() {});
      });
    }

    final coreCount =
        wb.activeReleaseBeats.where((b) => !b.isFullProductionEpic).length;
    final nextVer = wb.nextProgressiveVersionLabel;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isBuilding,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          modalSetState = setModalState;
          final bp = draft;
          final canApprove =
              !readOnly && !isLoading && !isBuilding && (bp?.isReadyToApprove ?? false);
          return Dialog(
            key: const ValueKey('full_production_blueprint_modal'),
            backgroundColor: bgSurface,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: borderBright),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: borderSubtle)),
                    ),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'ACT 2 · FULL PRODUCTION BLUEPRINT',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: textPrimary,
                          ),
                        ),
                        if (coreCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accentEmerald.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: accentEmerald.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              'E01–E${coreCount.toString().padLeft(2, '0')} Locked STABLE ✓',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: accentEmerald,
                              ),
                            ),
                          ),
                        Text(
                          readOnly
                              ? 'Approved scope for the full v1.0 game'
                              : 'Turn the finished Vertical Slice into the full v1.0 game',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Body
                  Flexible(
                    child: (isLoading || bp == null)
                        ? Padding(
                            key: const ValueKey('fp_blueprint_drafting_state'),
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: textMuted,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Drafting Full Production Blueprint…',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final sec in _fpSections)
                                  _buildFpSectionCard(
                                    sec: sec,
                                    bp: bp,
                                    controller: controllers[sec.key]!,
                                    readOnly: readOnly || isBuilding,
                                    onChanged: () => setModalState(() {}),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  // Footer
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: borderSubtle)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isBuilding) ...[
                          Expanded(
                            child: Text(
                              wb.agentProgressStep ??
                                  'Building $nextVer Full-Game Skeleton…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ],
                        TextButton(
                          key: const ValueKey('close_fp_blueprint_btn'),
                          onPressed: isBuilding
                              ? null
                              : () => Navigator.of(ctx).pop(),
                          child: Text(
                            readOnly ? 'Close' : 'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                          ),
                        ),
                        if (!readOnly) ...[
                          const SizedBox(width: 8),
                          ElevatedButton(
                            key: const ValueKey(
                              'approve_full_production_blueprint_btn',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentEmerald,
                              foregroundColor: isDark
                                  ? const Color(0xFF06281E)
                                  : Colors.white,
                              elevation: 0,
                            ),
                            onPressed: canApprove
                                ? () async {
                                    final current = draft!;
                                    for (final s in _fpSections) {
                                      _applyFpSectionText(
                                        current,
                                        s.key,
                                        controllers[s.key]!.text,
                                      );
                                    }
                                    wb.updateFullProductionBlueprint(current);
                                    setModalState(() => isBuilding = true);
                                    final ok = await wb
                                        .approveFullProductionBlueprintAndBuildSkeleton();
                                    if (!dialogOpen) return;
                                    if (ok) {
                                      if (ctx.mounted) Navigator.of(ctx).pop();
                                    } else {
                                      setModalState(() => isBuilding = false);
                                      if (context.mounted) {
                                        AppToast.show(
                                          context,
                                          'Could not build the Full-Game Skeleton. Check your Gemini key and try again.',
                                          icon: Icons.cloud_off_rounded,
                                          isDark: isDark,
                                          accentColor: accentAmber,
                                        );
                                      }
                                    }
                                  }
                                : null,
                            child: Text(
                              'Approve & Build $nextVer Skeleton →',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
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
          );
        },
      ),
    );
    dialogOpen = false;
    for (final c in controllers.values) {
      c.dispose();
    }
    if (mounted) _rebuild();
  }

  Widget _buildFpSectionCard({
    required ({
      String num,
      String title,
      String key,
      bool isList,
      String hint,
    }) sec,
    required FullProductionBlueprint bp,
    required TextEditingController controller,
    required bool readOnly,
    required VoidCallback onChanged,
  }) {
    final options = (bp.sectionOptions[sec.key] ?? const <String>[])
        .where((o) => o.trim().isNotEmpty)
        .take(3)
        .toList();
    return Container(
      key: ValueKey('fp_section_${sec.key}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgRecessed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${sec.num} · ${sec.title.toUpperCase()}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: textSecondary,
            ),
          ),
          if (!readOnly && options.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int oIdx = 0; oIdx < options.length; oIdx++)
                  InkWell(
                    key: ValueKey('fp_option_${sec.key}_$oIdx'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      final text = sec.isList
                          ? options[oIdx]
                              .split(RegExp(r'\s\|\s|\n'))
                              .map((l) => l.trim())
                              .where((l) => l.isNotEmpty)
                              .join('\n')
                          : options[oIdx].trim();
                      controller.text = text;
                      _applyFpSectionText(bp, sec.key, text);
                      onChanged();
                    },
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 240),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: bgSurface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: controller.text.trim() ==
                                  (sec.isList
                                      ? options[oIdx]
                                          .split(RegExp(r'\s\|\s|\n'))
                                          .map((l) => l.trim())
                                          .where((l) => l.isNotEmpty)
                                          .join('\n')
                                      : options[oIdx].trim())
                              ? textPrimary
                              : borderSubtle,
                        ),
                      ),
                      child: Text(
                        '${oIdx == 0 ? '★ ' : ''}${options[oIdx].trim()}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('fp_input_${sec.key}'),
            controller: controller,
            readOnly: readOnly,
            minLines: sec.isList ? 2 : 1,
            maxLines: sec.isList ? 6 : 2,
            onChanged: (val) {
              _applyFpSectionText(bp, sec.key, val);
              onChanged();
            },
            style: GoogleFonts.inter(fontSize: 12.5, color: textPrimary),
            decoration: InputDecoration(
              hintText: sec.hint,
              hintStyle: GoogleFonts.inter(fontSize: 12, color: textMuted),
              filled: true,
              fillColor: bgSurface,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: borderSubtle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
