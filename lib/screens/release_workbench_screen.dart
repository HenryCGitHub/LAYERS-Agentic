import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/epic_spec.dart';
import '../providers/workbench_provider.dart';
import '../theme/app_theme.dart';
import 'workbench/epic_domain_sheet.dart';
import 'workbench/feature_spec_sheet.dart';
import 'workbench/floating_ai_refine_dock.dart';
import 'workbench/plain_doc_widgets.dart';
import 'workbench/workbench_shared_widgets.dart';

/// Stage 2 Epic Domain & Feature Option A 2-column workspace (`1140px`).
/// Mounts inside [PlainDocumentShell]'s wide centered overlay (`inOverlay: true`),
/// or standalone in widget tests (`embeddedInShell: false`).
class ReleaseWorkbenchScreen extends StatefulWidget {
  final WorkbenchProvider workbench;
  final bool embeddedInShell;
  final bool inOverlay;

  const ReleaseWorkbenchScreen({
    super.key,
    required this.workbench,
    this.embeddedInShell = false,
    this.inOverlay = false,
  });

  @override
  State<ReleaseWorkbenchScreen> createState() => _ReleaseWorkbenchScreenState();
}

class _ReleaseWorkbenchScreenState extends State<ReleaseWorkbenchScreen> {
  final ScrollController _specScrollController = ScrollController();
  final TextEditingController _refineController = TextEditingController();

  String _lastSelectionKey = '';
  String? _passGateHint;
  String? _pendingAutoFocusFeatureId;
  int? _copiedTokens;
  Timer? _copyResetTimer;

  @override
  void initState() {
    super.initState();
    _consumeAutoFocus();
  }

  void _consumeAutoFocus() {
    final nextId = widget.workbench.consumeAutoFocusFeatureId();
    if (nextId != null) {
      _pendingAutoFocusFeatureId = nextId;
    }
  }

  @override
  void didUpdateWidget(covariant ReleaseWorkbenchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _consumeAutoFocus();
  }

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    _specScrollController.dispose();
    _refineController.dispose();
    super.dispose();
  }

  void _syncSelection(String selectionKey, FeatureSpec? feature) {
    _consumeAutoFocus();
    if (selectionKey != _lastSelectionKey) {
      _lastSelectionKey = selectionKey;
      _passGateHint = null;
      _copyResetTimer?.cancel();
      _copiedTokens = null;
      if (feature == null || feature.id != _pendingAutoFocusFeatureId) {
        _pendingAutoFocusFeatureId = null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_specScrollController.hasClients) {
          _specScrollController.jumpTo(0);
        }
      });
    }
  }

  void _triggerSilentCopy(String promptText) {
    Clipboard.setData(ClipboardData(text: promptText));
    final tok = (promptText.length / 4).ceil().clamp(1, 999999);
    _copyResetTimer?.cancel();
    setState(() => _copiedTokens = tok);
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copiedTokens = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final wb = widget.workbench;
    final epics = wb.activeReleaseEpics;
    final selectedEpic =
        wb.selectedEpicSpec ?? (epics.isNotEmpty ? epics.first : null);
    final selectedFeature = wb.selectedFeatureSpec;
    final selectionKey =
        '${wb.activeReleaseId}:${selectedEpic?.id}:${selectedFeature?.id}';

    _syncSelection(selectionKey, selectedFeature);

    final isDark = wb.isDark;
    final bgBase = AppTheme.bgBaseFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);

    if (selectedEpic == null) {
      return Material(
        color: bgBase,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Approve the Stage 1 Project Brief to launch v0.1.',
                  style: TextStyle(fontSize: 13.5, color: muted),
                ),
                const SizedBox(height: 12),
                PlainPrimaryButton(
                  label: 'Go to Project Brief',
                  isDark: isDark,
                  onPressed: () => wb.selectProjectBrief(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final workspace = _buildCenteredDocumentWorkspace(
      context,
      wb,
      epics,
      selectedEpic,
      selectedFeature,
      selectionKey,
    );

    return Material(color: bgBase, child: workspace);
  }

  Widget _buildCenteredDocumentWorkspace(
    BuildContext context,
    WorkbenchProvider wb,
    List<EpicSpec> epics,
    EpicSpec epic,
    FeatureSpec? feature,
    String selectionKey,
  ) {
    final isDark = wb.isDark;
    final border = AppTheme.borderFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final amber = AppTheme.accentAmberFor(isDark);

    final relVer = wb.activeReleaseVersionTag;
    final isLockedBaseline = wb.isSelectedFeatureLockedBaseline;
    final rollup = wb.epicFeatureRollup(epic);
    final releaseRollup = wb.activeReleaseFeatureRollup;
    final visibleEpicFeatures = wb.visibleFeaturesForEpic(epic);

    FeatureSpec? nextOpenFeature;
    for (final f in visibleEpicFeatures) {
      if (!f.isResolvedForRelease(relVer)) {
        nextOpenFeature = f;
        break;
      }
    }
    final primaryTargetFeature = nextOpenFeature ??
        (visibleEpicFeatures.isNotEmpty ? visibleEpicFeatures.first : null);
    final primaryEpicActionLabel = primaryTargetFeature == null
        ? 'Open Epic'
        : (nextOpenFeature != null
              ? '${rollup.passed == 0 ? 'Start' : 'Continue'} ${primaryTargetFeature.code} →'
              : 'Inspect ${primaryTargetFeature.code} →');
    final projTitle = (wb.conceptDraft?.normalizedTitle ??
            wb.activeProject?.title ??
            'Brief')
        .trim();

    final copyIdleLabel = feature != null && feature.openFixesCount > 0
        ? 'Copy CoPilot [FIX] Prompt (${feature.openFixesCount})'
        : (feature != null &&
                  relVer != 'v0.1' &&
                  feature.releaseDelta.trim().isNotEmpty
              ? 'Copy CoPilot Delta Prompt'
              : 'Copy CoPilot Prompt');
    final copyIcon = _copiedTokens != null
        ? Icons.check_rounded
        : (feature != null && feature.openFixesCount > 0
              ? Icons.build_outlined
              : Icons.bolt_rounded);
    final copyLabel =
        _copiedTokens != null ? 'Copied (~$_copiedTokens tok)' : copyIdleLabel;

    final autoFocusFeature =
        feature != null && _pendingAutoFocusFeatureId == feature.id;

    ({String label, VoidCallback onTap})? overlayPrevTarget;
    ({String label, VoidCallback onTap})? overlayNextTarget;
    if (widget.inOverlay) {
      if (feature != null) {
        final orderedFeatures = <({String epicId, FeatureSpec feat})>[
          for (final ep in epics)
            for (final f in wb.visibleFeaturesForEpic(ep))
              (epicId: ep.id, feat: f),
        ];
        final currentIdx = orderedFeatures.indexWhere(
          (item) => item.feat.id == feature.id,
        );
        if (currentIdx > 0) {
          final prev = orderedFeatures[currentIdx - 1];
          overlayPrevTarget = (
            label: prev.feat.code,
            onTap: () {
              FocusManager.instance.primaryFocus?.unfocus();
              wb.selectFeature(prev.epicId, prev.feat.id);
            },
          );
        }
        if (currentIdx >= 0 && currentIdx < orderedFeatures.length - 1) {
          final next = orderedFeatures[currentIdx + 1];
          overlayNextTarget = (
            label: next.feat.code,
            onTap: () {
              FocusManager.instance.primaryFocus?.unfocus();
              wb.selectFeature(next.epicId, next.feat.id);
            },
          );
        }
      } else {
        final epIdx = epics.indexWhere((ep) => ep.id == epic.id);
        if (epIdx > 0) {
          final prevEp = epics[epIdx - 1];
          overlayPrevTarget = (
            label: prevEp.code,
            onTap: () {
              FocusManager.instance.primaryFocus?.unfocus();
              wb.selectEpic(prevEp.id);
            },
          );
        }
        if (epIdx >= 0 && epIdx < epics.length - 1) {
          final nextEp = epics[epIdx + 1];
          overlayNextTarget = (
            label: nextEp.code,
            onTap: () {
              FocusManager.instance.primaryFocus?.unfocus();
              wb.selectEpic(nextEp.id);
            },
          );
        }
      }
    }

    final breadcrumbsWrap = Wrap(
      key: const ValueKey('stage2_breadcrumbs'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        PlainTextLink(
          key: const ValueKey('crumb_project'),
          label: projTitle,
          isDark: isDark,
          mono: true,
          fontSize: 11.5,
          color: muted,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            wb.selectProjectBrief();
          },
        ),
        Text(
          '/',
          style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: muted),
        ),
        PlainTextLink(
          key: const ValueKey('crumb_release'),
          label: widget.inOverlay ? '$relVer Table' : relVer,
          isDark: isDark,
          mono: true,
          fontSize: 11.5,
          color: muted,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            wb.selectReleaseSpec();
          },
        ),
        Text(
          '/',
          style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: muted),
        ),
        PlainTextLink(
          key: const ValueKey('crumb_epic'),
          label: epic.code,
          isDark: isDark,
          mono: true,
          fontSize: 11.5,
          color: feature == null ? primary : muted,
          fontWeight: feature == null ? FontWeight.w700 : FontWeight.w500,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            wb.selectEpic(epic.id);
          },
        ),
        if (feature != null) ...[
          Text(
            '/',
            style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: muted),
          ),
          PlainTextLink(
            key: const ValueKey('crumb_feature'),
            label: feature.code,
            isDark: isDark,
            mono: true,
            fontSize: 11.5,
            color: primary,
            fontWeight: FontWeight.w700,
            onTap: () => wb.selectFeature(epic.id, feature.id),
          ),
        ],
      ],
    );

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border, width: 1)),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kPlainDocWideMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.inOverlay)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: breadcrumbsWrap),
                        const SizedBox(width: 10),
                        PlainTextLink(
                          key: const ValueKey('overlay_prev_btn'),
                          label: overlayPrevTarget != null
                              ? '← ${overlayPrevTarget.label}'
                              : '← Prev',
                          isDark: isDark,
                          mono: true,
                          fontSize: 11.5,
                          color: secondary,
                          onTap: overlayPrevTarget?.onTap,
                        ),
                        const SizedBox(width: 10),
                        PlainTextLink(
                          key: const ValueKey('overlay_next_btn'),
                          label: overlayNextTarget != null
                              ? '${overlayNextTarget.label} →'
                              : 'Next →',
                          isDark: isDark,
                          mono: true,
                          fontSize: 11.5,
                          color: secondary,
                          onTap: overlayNextTarget?.onTap,
                        ),
                        const SizedBox(width: 12),
                        PlainTextLink(
                          key: const ValueKey('close_workbench_overlay_btn'),
                          label: '✕ Esc',
                          isDark: isDark,
                          mono: true,
                          fontSize: 11.5,
                          color: primary,
                          fontWeight: FontWeight.w600,
                          onTap: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            wb.selectReleaseSpec();
                          },
                        ),
                      ],
                    )
                  else
                    breadcrumbsWrap,
                  const SizedBox(height: 10),

                    // Inline Title
                    if (feature == null)
                      PlainEditableLineField(
                        fieldKey: const ValueKey('epic_title_input'),
                        value: epic.title,
                        isDark: isDark,
                        hintText: 'Epic title...',
                        style: AppTheme.displayFont(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                        onCommit: (val) =>
                            wb.updateEpicScope(epic.id, title: val),
                      )
                    else
                      KeyedSubtree(
                        key: ValueKey('feature_title_wrap_${feature.id}'),
                        child: PlainEditableLineField(
                          fieldKey: const ValueKey('feature_title_input'),
                          value: feature.title,
                          isDark: isDark,
                          readOnly: isLockedBaseline,
                          autoFocusAndSelect: autoFocusFeature,
                          hintText: 'Feature title...',
                          style: AppTheme.displayFont(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                          onCommit: (val) => wb.updateFeatureScope(
                            epic.id,
                            feature.id,
                            title: val,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      feature == null
                          ? 'EPIC · ${rollup.passed}/${rollup.total} FEATURES PASSED'
                          : 'FEATURE ${feature.code} · ${feature.sliceTime} · ${wb.unrealArchitectureMode.shortLabel}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Flat Action Row
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (feature == null) ...[
                          PlainPrimaryButton(
                            key: const ValueKey(
                              'epic_inspect_first_feature_btn',
                            ),
                            label: primaryEpicActionLabel,
                            isDark: isDark,
                            onPressed: primaryTargetFeature == null
                                ? null
                                : () {
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                    wb.selectFeature(
                                      epic.id,
                                      primaryTargetFeature.id,
                                    );
                                  },
                          ),
                          PopupMenuButton<String>(
                            key: const ValueKey('epic_more_menu_btn'),
                            tooltip: 'Architecture Brief Options',
                            color: AppTheme.bgPanelFor(isDark),
                            surfaceTintColor: Colors.transparent,
                            onSelected: (choice) {
                              if (choice == 'preview_brief') {
                                showCoPilotPromptPreviewDialog(
                                  context,
                                  title: '${epic.code} · Architecture Brief',
                                  promptText:
                                      wb.activeEpicArchitecturePrompt(epic),
                                  readableText:
                                      wb.activeEpicReadableBrief(epic),
                                  isDark: isDark,
                                );
                              } else if (choice == 'copy_brief') {
                                copyPromptWithToast(
                                  context,
                                  promptText:
                                      wb.activeEpicArchitecturePrompt(epic),
                                  toastMessage:
                                      'Copied ${epic.code} Architecture Brief',
                                  isDark: isDark,
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem<String>(
                                key: const ValueKey('preview_epic_brief_btn'),
                                value: 'preview_brief',
                                child: Text(
                                  'Preview Architecture Brief',
                                  style: TextStyle(fontSize: 12, color: primary),
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'copy_brief',
                                child: Text(
                                  'Copy Architecture Brief',
                                  style:
                                      TextStyle(fontSize: 12, color: secondary),
                                ),
                              ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Text(
                                '⋯ Brief',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ),
                          ),
                        ] else ...[
                          PlainPrimaryButton(
                            key: const ValueKey('copy_copilot_prompt_btn'),
                            label: copyLabel,
                            icon: copyIcon,
                            isDark: isDark,
                            fillColor: _copiedTokens != null ? green : focal,
                            onPressed: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              _triggerSilentCopy(
                                wb.activeFeatureBuildPrompt(epic, feature),
                              );
                            },
                          ),
                          PlainPrimaryButton(
                            key: const ValueKey('preview_copilot_prompt_btn'),
                            label: 'Preview DSL',
                            outlined: true,
                            isDark: isDark,
                            onPressed: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              showCoPilotPromptPreviewDialog(
                                context,
                                title: '${feature.code} · CoPilot Prompt',
                                promptText:
                                    wb.activeFeatureBuildPrompt(epic, feature),
                                readableText:
                                    wb.activeFeatureReadablePrompt(
                                      epic,
                                      feature,
                                    ),
                                isDark: isDark,
                              );
                            },
                          ),
                          if (!isLockedBaseline) ...[
                            if (feature.isPassed)
                              PlainPrimaryButton(
                                key: const ValueKey('reopen_feature_btn'),
                                label: 'Reopen',
                                outlined: true,
                                isDark: isDark,
                                onPressed: () =>
                                    wb.reopenFeature(epic.id, feature.id),
                              )
                            else
                              PlainPrimaryButton(
                                key: const ValueKey('pass_feature_btn'),
                                label: 'Pass Feature ✓',
                                outlined: true,
                                isDark: isDark,
                                foregroundColor:
                                    wb.canPassFeature(feature) ? green : muted,
                                onPressed: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  final passed = wb.passFeature(
                                    epic.id,
                                    feature.id,
                                  );
                                  if (!passed) {
                                    setState(() {
                                      _passGateHint = feature
                                              .openFixes
                                              .isNotEmpty
                                          ? 'Resolve all open [FIX] notes before passing this Feature.'
                                          : 'Check every Playtest Gate item before passing this Feature.';
                                    });
                                  }
                                },
                              ),
                            if (wb.canDeleteFeature(epic, feature))
                              PlainTextLink(
                                key: const ValueKey('delete_feature_btn'),
                                label: 'Delete',
                                isDark: isDark,
                                fontSize: 12,
                                color: muted,
                                onTap: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  wb.deleteUnbuiltFeature(epic.id, feature.id);
                                },
                              ),
                          ],
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _specScrollController,
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kPlainDocWideMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wb.isActiveReleaseComplete) ...[
                      const SizedBox(height: 14),
                      Container(
                        key: const ValueKey('release_complete_banner'),
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: green, width: 2),
                            bottom: BorderSide(color: border, width: 1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                releaseRollup.passed < releaseRollup.total
                                    ? '✓ $relVer Active Features Complete (${releaseRollup.passed}/${releaseRollup.total} Total Passed)'
                                    : '✓ $relVer Complete (${releaseRollup.passed}/${releaseRollup.total} Features Passed)',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: green,
                                ),
                              ),
                            ),
                            PlainTextLink(
                              key: const ValueKey(
                                'release_complete_plan_next_btn',
                              ),
                              label: '${wb.nextReleaseActionLabel} →',
                              isDark: isDark,
                              color: green,
                              onTap: wb.isDraftingProgressive
                                  ? null
                                  : () {
                                      FocusManager.instance.primaryFocus
                                          ?.unfocus();
                                      wb.openInPagePlanNextRelease();
                                    },
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (isLockedBaseline && feature != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        key: const ValueKey('locked_baseline_banner'),
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: amber, width: 2),
                            bottom: BorderSide(color: border, width: 1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Locked ${feature.introducedIn} baseline in $relVer. Read-only unless upgraded via +DELTA.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: secondary,
                                ),
                              ),
                            ),
                            PlainTextLink(
                              key: const ValueKey('open_in_baseline_btn'),
                              label: 'Open in ${feature.introducedIn} →',
                              isDark: isDark,
                              color: amber,
                              onTap: wb.openSelectedFeatureInBaselineRelease,
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (feature == null)
                      EpicDomainSheet(
                        workbench: wb,
                        epic: epic,
                        isDark: isDark,
                        selectionKey: selectionKey,
                      )
                    else
                      FeatureSpecSheet(
                        workbench: wb,
                        epic: epic,
                        feature: feature,
                        isLockedBaseline: isLockedBaseline,
                        isDark: isDark,
                        selectionKey: selectionKey,
                        passGateHint: _passGateHint,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        if (feature == null || !isLockedBaseline)
          FloatingAiRefineDock(
            isDark: isDark,
            targetBadge: feature == null
                ? 'AI · ${epic.code}'
                : 'AI · ${feature.code}',
            hintText: feature == null
                ? 'Refine ${epic.code} owners, states, or domain cuts...'
                : 'Refine ${feature.code} controls, tuning (cm / cm/s), cues, or PIE checks...',
            isBusy: wb.isRefiningStage2,
            canUndo: wb.canUndoStage2Edit,
            summaryText: wb.lastStage2RefineSummary,
            errorText: wb.stage2RefineError,
            quickPrompts: feature == null
                ? const [
                    'Add shared /Game/ owner',
                    'Add interrupt rule',
                    'Add scope cut',
                  ]
                : const [
                    'Set DashDistance to 550 cm',
                    'Add impact VFX & SFX cue',
                    'Add PIE gate check',
                  ],
            externalController: _refineController,
            inputKey: const ValueKey('stage2_ai_refine_input'),
            applyBtnKey: const ValueKey('stage2_ai_refine_apply_btn'),
            undoBtnKey: const ValueKey('stage2_ai_refine_undo_btn'),
            ideasBtnKey: const ValueKey('stage2_ai_ideas_btn'),
            ideasStripKey: const ValueKey('stage2_ai_ideas_strip'),
            onApply: (instruction) async {
              FocusManager.instance.primaryFocus?.unfocus();
              final bool ok = feature == null
                  ? (await wb.applyStage2EpicRefine(epic.id, instruction)) !=
                        null
                  : (await wb.applyStage2FeatureRefine(
                          epic.id,
                          feature.id,
                          instruction,
                        )) !=
                        null;
              if (ok && mounted) {
                _refineController.clear();
              }
            },
            onUndo: wb.undoStage2Edit,
            onDismissError: wb.dismissStage2RefineError,
          ),
      ],
    );
  }
}
