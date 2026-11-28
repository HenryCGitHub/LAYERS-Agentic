import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import 'plain_doc_widgets.dart';

/// Shared slim 1-line flat AI Refine bar with expandable prompt links and
/// inline Undo / Error status.
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
  final bool alwaysShowUndo;
  final Widget? customErrorBanner;
  final double maxWidth;

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
    this.alwaysShowUndo = false,
    this.customErrorBanner,
    this.maxWidth = kPlainDocWideMaxWidth,
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
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.externalController == null &&
          (widget.errorText == null || widget.errorText!.trim().isEmpty)) {
        _ctrl.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final border = AppTheme.borderFor(isDark);
    final baseBg = AppTheme.bgBaseFor(isDark);
    final primary = AppTheme.textPrimaryFor(isDark);
    final secondary = AppTheme.textSecondaryFor(isDark);
    final muted = AppTheme.textMutedFor(isDark);
    final focal = AppTheme.focalAccentFor(isDark);
    final focalFg = AppTheme.focalAccentFgFor(isDark);
    final green = AppTheme.accentGreenFor(isDark);
    final red = AppTheme.accentRedFor(isDark);

    final showChips =
        widget.quickPrompts.isNotEmpty && (_showIdeas || _focusNode.hasFocus);

    return Material(
      color: baseBg,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: border, width: 1)),
        ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.customErrorBanner != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: widget.customErrorBanner!,
                ),
              ] else if (widget.errorText != null &&
                  widget.errorText!.trim().isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 13, color: red),
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
                          child: Icon(Icons.close, size: 13, color: red),
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
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      for (final tip in widget.quickPrompts)
                        InkWell(
                          onTap: widget.isBusy
                              ? null
                              : () {
                                  _ctrl.text = tip;
                                  _ctrl.selection = TextSelection.collapsed(
                                    offset: tip.length,
                                  );
                                  _focusNode.requestFocus();
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              tip,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: secondary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _focusNode.hasFocus ? focal : border,
                      width: 1,
                    ),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, dockConstraints) {
                    final compact = dockConstraints.maxWidth < 500;
                    final fullBadge = widget.targetBadge.startsWith('✨')
                        ? widget.targetBadge
                        : '✨ ${widget.targetBadge}';
                    return Row(
                      children: [
                        Text(
                          compact ? '✨' : fullBadge,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: widget.inputKey,
                            controller: _ctrl,
                            focusNode: _focusNode,
                            enabled: !widget.isBusy,
                            style: TextStyle(fontSize: 13, color: primary),
                            decoration: InputDecoration(
                              hintText: widget.hintText,
                              hintStyle: TextStyle(fontSize: 12.5, color: muted),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 2,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              minimumSize: const Size(0, 26),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              _showIdeas ? 'Hide' : 'Ideas',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _showIdeas ? primary : muted,
                              ),
                            ),
                          ),
                        ],
                        if ((widget.canUndo || widget.alwaysShowUndo) &&
                            widget.onUndo != null) ...[
                          const SizedBox(width: 2),
                          TextButton(
                            key: widget.undoBtnKey,
                            onPressed: (widget.isBusy || !widget.canUndo)
                                ? null
                                : widget.onUndo,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              minimumSize: const Size(0, 26),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: secondary,
                              disabledForegroundColor:
                                  muted.withValues(alpha: 0.45),
                            ),
                            child: const Text(
                              'Undo',
                              style: TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        TextButton(
                          key: widget.applyBtnKey,
                          onPressed: widget.isBusy ? null : _submit,
                          style: TextButton.styleFrom(
                            backgroundColor: focal,
                            foregroundColor: focalFg,
                            disabledBackgroundColor:
                                AppTheme.bgSurfaceActiveFor(isDark),
                            disabledForegroundColor: muted,
                            elevation: 0,
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 4,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          child: widget.isBusy
                              ? SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: focalFg,
                                  ),
                                )
                              : const Text(
                                  'Run',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
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
    ),
    );
  }
}
