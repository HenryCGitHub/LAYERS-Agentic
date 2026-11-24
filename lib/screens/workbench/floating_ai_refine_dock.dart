import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// Shared slim 1-line floating AI Refine dock (`✨ AI · [Target]`) with
/// expandable quick-prompt chips and inline Undo / Error status.
class FloatingAiRefineDock extends StatefulWidget {
  final bool isDark;
  final String targetBadge;
  final String hintText;
  final bool isBusy;
  final bool canUndo;
  final String? summaryText;
  final String? errorText;
  final List<String> quickPrompts;
  final TextEditingController? externalController;
  final Key? inputKey;
  final Key? applyBtnKey;
  final Key? undoBtnKey;
  final Key? ideasBtnKey;
  final Key? ideasStripKey;
  final Future<void> Function(String instruction) onApply;
  final VoidCallback? onUndo;
  final VoidCallback? onDismissError;

  const FloatingAiRefineDock({
    super.key,
    required this.isDark,
    required this.targetBadge,
    required this.hintText,
    required this.isBusy,
    required this.canUndo,
    this.summaryText,
    this.errorText,
    this.quickPrompts = const <String>[],
    this.externalController,
    this.inputKey,
    this.applyBtnKey,
    this.undoBtnKey,
    this.ideasBtnKey,
    this.ideasStripKey,
    required this.onApply,
    this.onUndo,
    this.onDismissError,
  });

  @override
  State<FloatingAiRefineDock> createState() => _FloatingAiRefineDockState();
}

class _FloatingAiRefineDockState extends State<FloatingAiRefineDock> {
  late final TextEditingController _ownController;
  final FocusNode _focusNode = FocusNode();
  bool _showIdeas = false;

  TextEditingController get _ctrl =>
      widget.externalController ?? _ownController;

  @override
  void initState() {
    super.initState();
    _ownController = TextEditingController();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant FloatingAiRefineDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetBadge != widget.targetBadge) {
      _showIdeas = false;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _ownController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.isBusy) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    await widget.onApply(text);
    if (!mounted) return;
    if (widget.errorText == null) {
      _ctrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final border = AppTheme.borderFor(isDark);
    final panelBg = AppTheme.bgPanelFor(isDark);
    final surfaceBg = AppTheme.bgSurfaceRaisedFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final cyan = AppTheme.accentCyanFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final red = AppTheme.accentRedFor(isDark);

    final showChips =
        widget.quickPrompts.isNotEmpty && (_showIdeas || _focusNode.hasFocus);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.errorText != null &&
                  widget.errorText!.trim().isNotEmpty) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: red.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 14, color: red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.errorText!,
                          style: TextStyle(fontSize: 11.5, color: red),
                        ),
                      ),
                      if (widget.onDismissError != null)
                        InkWell(
                          onTap: widget.onDismissError,
                          child: Icon(Icons.close, size: 14, color: red),
                        ),
                    ],
                  ),
                ),
              ] else if (widget.summaryText != null &&
                  widget.summaryText!.trim().isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '✓ ${widget.summaryText!}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: green,
                    ),
                  ),
                ),
              ],
              if (showChips) ...[
                Padding(
                  key: widget.ideasStripKey,
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tip in widget.quickPrompts)
                        ActionChip(
                          label: Text(
                            tip,
                            style: TextStyle(fontSize: 11.5, color: secondary),
                          ),
                          backgroundColor: surfaceBg,
                          side: BorderSide(color: border),
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.isBusy
                              ? null
                              : () {
                                  _ctrl.text = tip;
                                  _ctrl.selection = TextSelection.collapsed(
                                    offset: tip.length,
                                  );
                                  _focusNode.requestFocus();
                                },
                        ),
                    ],
                  ),
                ),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: surfaceBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(color: border),
                ),
                child: LayoutBuilder(
                  builder: (context, dockConstraints) {
                    final compact = dockConstraints.maxWidth < 500;
                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: cyan.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusXs),
                            border: Border.all(
                              color: cyan.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            compact ? '✨' : '✨ ${widget.targetBadge}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: cyan,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: widget.inputKey,
                            controller: _ctrl,
                            focusNode: _focusNode,
                            enabled: !widget.isBusy,
                            style: TextStyle(fontSize: 12.5, color: primary),
                            decoration: InputDecoration(
                              hintText: widget.hintText,
                              hintStyle: TextStyle(fontSize: 12, color: muted),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 6,
                              ),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                        if (widget.quickPrompts.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          TextButton(
                            key: widget.ideasBtnKey,
                            onPressed: () =>
                                setState(() => _showIdeas = !_showIdeas),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 5 : 8,
                                vertical: 4,
                              ),
                              minimumSize: const Size(0, 28),
                            ),
                            child: Text(
                              _showIdeas ? 'Hide' : 'Ideas',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _showIdeas ? cyan : muted,
                              ),
                            ),
                          ),
                        ],
                        if (widget.canUndo && widget.onUndo != null) ...[
                          const SizedBox(width: 4),
                          OutlinedButton.icon(
                            key: widget.undoBtnKey,
                            onPressed: widget.isBusy ? null : widget.onUndo,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 30),
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 6 : 8,
                                vertical: 4,
                              ),
                            ),
                            icon: const Icon(Icons.undo_rounded, size: 13.5),
                            label: Text(
                              compact ? '' : 'Undo',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        ElevatedButton(
                          key: widget.applyBtnKey,
                          onPressed: widget.isBusy ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 30),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                          ),
                          child: widget.isBusy
                              ? const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Apply',
                                  style: TextStyle(fontSize: 12),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
