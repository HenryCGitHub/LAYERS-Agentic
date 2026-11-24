import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/epic_spec.dart';
import '../../theme/app_theme.dart';
import '../../utils/unreal_prompt_compactor.dart';

/// Copies [promptText] to the system clipboard and surfaces a studio toast.
Future<void> copyPromptWithToast(
  BuildContext context, {
  required String promptText,
  required String toastMessage,
  required bool isDark,
}) async {
  await Clipboard.setData(ClipboardData(text: promptText));
  if (!context.mounted) return;
  AppToast.show(context, toastMessage, isDark: isDark);
}

/// Opens a scrollable modal inspecting Compact CoPilot DSL or Readable Markdown before copying.
Future<void> showCoPilotPromptPreviewDialog(
  BuildContext context, {
  required String title,
  required String promptText,
  String? readableText,
  required bool isDark,
}) async {
  final border = AppTheme.borderFor(isDark);
  final primary = AppTheme.textPrimaryFor(isDark);
  final muted = AppTheme.textMutedFor(isDark);
  final cyan = AppTheme.accentCyanFor(isDark);
  final green = AppTheme.accentGreenFor(isDark);
  final hasReadable = readableText != null && readableText.trim().isNotEmpty;
  final savings = hasReadable
      ? UnrealPromptCompactor.compareSavings(promptText, readableText)
      : null;
  final compactTokens =
      savings?.compactTokens ?? UnrealPromptCompactor.estimateTokens(promptText);
  var showReadable = false;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setDialogState) {
        final activeText =
            (showReadable && hasReadable) ? readableText : promptText;
        final badgeLabel = (savings != null && savings.savedPercent > 0)
            ? (showReadable
                ? 'Paste size: ~${savings.readableTokens} tok (Human MD)'
                : 'Paste size: ~$compactTokens tok · -${savings.savedPercent}% vs MD')
            : 'Paste size: ~$compactTokens tok';
        final highlightSaved =
            !showReadable && savings != null && savings.savedPercent > 0;

        return Dialog(
          backgroundColor: AppTheme.bgSurfaceRaisedFor(isDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            side: BorderSide(color: border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 660),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 18, color: cyan),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: AppTheme.displayFont(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: primary,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('close_copilot_preview_btn'),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        icon: Icon(Icons.close, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (hasReadable)
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.bgSurfaceRecessedFor(isDark),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                            border: Border.all(color: border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PreviewModePill(
                                key: const ValueKey('preview_mode_compact_btn'),
                                label: 'Compact DSL',
                                selected: !showReadable,
                                accent: cyan,
                                muted: muted,
                                onTap: () =>
                                    setDialogState(() => showReadable = false),
                              ),
                              _PreviewModePill(
                                key: const ValueKey(
                                  'preview_mode_readable_btn',
                                ),
                                label: 'Readable View',
                                selected: showReadable,
                                accent: cyan,
                                muted: muted,
                                onTap: () =>
                                    setDialogState(() => showReadable = true),
                              ),
                            ],
                          ),
                        ),
                      Container(
                        key: const ValueKey('copilot_preview_token_badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: highlightSaved
                              ? green.withValues(alpha: 0.12)
                              : AppTheme.bgSurfaceRecessedFor(isDark),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSm,
                          ),
                          border: Border.all(
                            color: highlightSaved
                                ? green.withValues(alpha: 0.45)
                                : border,
                          ),
                        ),
                        child: Text(
                          badgeLabel,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: highlightSaved ? green : muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Compiled locally in memory (0 AI tokens spent by LAYERS)',
                    key: const ValueKey('copilot_preview_local_note'),
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurfaceRecessedFor(isDark),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(color: border),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          activeText,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11.5,
                            height: 1.45,
                            color: primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        child: const Text('Close'),
                      ),
                      if (showReadable && hasReadable) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          key: const ValueKey(
                            'dialog_copy_readable_prompt_btn',
                          ),
                          onPressed: () async {
                            await copyPromptWithToast(
                              dialogCtx,
                              promptText: readableText,
                              toastMessage:
                                  'Copied readable Markdown spec to clipboard',
                              isDark: isDark,
                            );
                          },
                          icon: const Icon(Icons.article_outlined, size: 15),
                          label: const Text('Copy Readable'),
                        ),
                      ],
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        key: const ValueKey('dialog_copy_copilot_prompt_btn'),
                        onPressed: () async {
                          await copyPromptWithToast(
                            dialogCtx,
                            promptText: promptText,
                            toastMessage: 'Copied CoPilot prompt to clipboard',
                            isDark: isDark,
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 15),
                        label: Text(
                          hasReadable ? 'Copy CoPilot DSL' : 'Copy Prompt',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _PreviewModePill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final Color muted;
  final VoidCallback onTap;

  const _PreviewModePill({
    super.key,
    required this.label,
    required this.selected,
    required this.accent,
    required this.muted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm - 1),
        ),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? accent : muted,
          ),
        ),
      ),
    );
  }
}

class OutlinerReleasePill extends StatelessWidget {
  final String label;
  final String goal;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const OutlinerReleasePill({
    super.key,
    required this.label,
    required this.goal,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? cyan.withValues(alpha: 0.1)
              : AppTheme.bgSurfaceFor(isDark),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
            color: isActive ? cyan.withValues(alpha: 0.65) : border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ),
                if (isActive)
                  Text(
                    'Active',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: cyan,
                    ),
                  ),
              ],
            ),
            if (goal.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                goal,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HeaderPill extends StatelessWidget {
  final String label;
  final Color color;

  const HeaderPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class EpicSectionCard extends StatelessWidget {
  final bool isDark;
  final String code;
  final String title;
  final Widget child;
  final Widget? trailing;

  const EpicSectionCard({
    super.key,
    required this.isDark,
    required this.code,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceRaisedFor(isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.borderFor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, cardConstraints) {
              final titleStyle = AppTheme.displayFont(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimaryFor(isDark),
              );
              final codeWidget = Text(
                code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentCyanFor(isDark),
                ),
              );
              if (trailing != null && cardConstraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        codeWidget,
                        const SizedBox(width: 8),
                        Expanded(child: Text(title, style: titleStyle)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    trailing!,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  codeWidget,
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: titleStyle)),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class LiveTuningChip extends StatefulWidget {
  final EpicTuningParam param;
  final bool isDark;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final Key? inputKey;
  final VoidCallback? onDelete;
  final Key? deleteKey;

  const LiveTuningChip({
    super.key,
    this.inputKey,
    required this.param,
    required this.isDark,
    this.readOnly = false,
    required this.onChanged,
    this.onDelete,
    this.deleteKey,
  });

  @override
  State<LiveTuningChip> createState() => LiveTuningChipState();
}

class LiveTuningChipState extends State<LiveTuningChip> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.param.value);
  }

  @override
  void didUpdateWidget(covariant LiveTuningChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.param.value != widget.param.value &&
        _controller.text.trim() != widget.param.value.trim()) {
      _controller.value = TextEditingValue(
        text: widget.param.value,
        selection: TextSelection.collapsed(offset: widget.param.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.borderFor(widget.isDark);
    final cyan = AppTheme.accentCyanFor(widget.isDark);
    final muted = AppTheme.textMutedFor(widget.isDark);
    final primary = AppTheme.textPrimaryFor(widget.isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceFor(widget.isDark),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.param.key}:',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: TextField(
              key: widget.inputKey,
              controller: _controller,
              readOnly: widget.readOnly,
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: widget.readOnly ? muted : cyan,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              ),
              onChanged: widget.readOnly ? null : widget.onChanged,
            ),
          ),
          if (widget.param.unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              widget.param.unit,
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: muted),
            ),
          ],
          if (!widget.readOnly && widget.onDelete != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Remove variable',
              child: InkWell(
                key: widget.deleteKey,
                onTap: widget.onDelete,
                borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 13, color: muted),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
