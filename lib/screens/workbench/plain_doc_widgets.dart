import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Shared plain-document UI primitives (zero cards, shadows, or pill chrome).
class PlainEditableLineField extends StatefulWidget {
  final String value;
  final bool isDark;
  final ValueChanged<String> onCommit;
  final ValueChanged<String>? onChanged;
  final Key? fieldKey;
  final String? hintText;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final int maxLines;
  final int? minLines;
  final bool multiLine;
  final bool autoFocusAndSelect;
  final bool readOnly;
  final bool trimOnCommit;
  final bool allowEmpty;
  final EdgeInsetsGeometry padding;

  const PlainEditableLineField({
    super.key,
    required this.value,
    required this.isDark,
    required this.onCommit,
    this.onChanged,
    this.fieldKey,
    this.hintText,
    this.style,
    this.hintStyle,
    this.maxLines = 1,
    this.minLines,
    this.multiLine = false,
    this.autoFocusAndSelect = false,
    this.readOnly = false,
    this.trimOnCommit = true,
    this.allowEmpty = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
  });

  @override
  State<PlainEditableLineField> createState() => _PlainEditableLineFieldState();
}

class _PlainEditableLineFieldState extends State<PlainEditableLineField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;
  late String _lastSyncedText;
  late String _lastCommitted;
  bool _dirty = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _lastSyncedText = widget.value;
    _lastCommitted = widget.value;
    _ctrl = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    if (widget.autoFocusAndSelect && !widget.readOnly) {
      _scheduleFocusAndSelect();
    }
  }

  void _scheduleFocusAndSelect() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.readOnly) return;
      _focusNode.requestFocus();
      _ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _ctrl.text.length,
      );
    });
  }

  @override
  void didUpdateWidget(covariant PlainEditableLineField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final keyChanged = oldWidget.fieldKey != widget.fieldKey;
    if (keyChanged || (!_focusNode.hasFocus && widget.value != _lastSyncedText)) {
      _lastSyncedText = widget.value;
      _lastCommitted = widget.value;
      _dirty = false;
      if (_ctrl.text != widget.value) {
        _ctrl.text = widget.value;
      }
      if (widget.autoFocusAndSelect && !widget.readOnly && keyChanged) {
        _scheduleFocusAndSelect();
      }
    } else if (!oldWidget.autoFocusAndSelect &&
        widget.autoFocusAndSelect &&
        !widget.readOnly) {
      _scheduleFocusAndSelect();
    }
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() {});
    if (!_focusNode.hasFocus) {
      _commitIfNeeded();
    }
  }

  void _commitIfNeeded() {
    if (widget.readOnly || !_dirty) return;
    final next = widget.trimOnCommit ? _ctrl.text.trim() : _ctrl.text;
    if (!widget.allowEmpty && next.isEmpty) {
      _ctrl.text = _lastSyncedText;
      _dirty = false;
      return;
    }
    _dirty = false;
    if (next == _lastCommitted) return;
    _lastCommitted = next;
    _lastSyncedText = next;
    widget.onCommit(next);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final focused = _focusNode.hasFocus && !widget.readOnly;
    final underlineColor = focused
        ? AppTheme.focalAccentFor(isDark)
        : (_hovered && !widget.readOnly
            ? AppTheme.borderFor(isDark)
            : Colors.transparent);
    final effectiveStyle = widget.style ??
        TextStyle(
          fontSize: 13.5,
          height: 1.45,
          color: AppTheme.textPrimaryFor(isDark),
        );
    final effectiveHintStyle = widget.hintStyle ??
        effectiveStyle.copyWith(
          color: AppTheme.textMutedFor(isDark),
        );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: underlineColor, width: 1),
          ),
        ),
        child: TextField(
          key: widget.fieldKey,
          controller: _ctrl,
          focusNode: _focusNode,
          readOnly: widget.readOnly,
          minLines: widget.minLines ?? 1,
          maxLines: widget.multiLine ? null : widget.maxLines,
          textInputAction:
              widget.multiLine ? TextInputAction.newline : TextInputAction.done,
          style: effectiveStyle,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hintText,
            hintStyle: effectiveHintStyle,
            filled: false,
            contentPadding: widget.padding,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onChanged: (val) {
            _dirty = val != _lastCommitted;
            widget.onChanged?.call(val);
          },
          onSubmitted: widget.multiLine ? null : (_) => _commitIfNeeded(),
        ),
      ),
    );
  }
}

class PlainSectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  final String? trailingText;
  final Widget? trailing;
  final bool showDivider;
  final EdgeInsetsGeometry padding;

  const PlainSectionHeader({
    super.key,
    required this.title,
    required this.isDark,
    this.trailingText,
    this.trailing,
    this.showDivider = true,
    this.padding = const EdgeInsets.only(bottom: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.borderFor(isDark), width: 1),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
                color: AppTheme.textMutedFor(isDark),
              ),
            ),
          ),
          if (trailingText != null)
            Text(
              trailingText!,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppTheme.textMutedFor(isDark),
              ),
            ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class PlainHoverRemoveRow extends StatefulWidget {
  final Widget child;
  final VoidCallback? onRemove;
  final bool isDark;
  final Key? removeKey;
  final String removeTooltip;
  final bool alwaysShow;
  final bool showBottomBorder;
  final EdgeInsetsGeometry padding;

  const PlainHoverRemoveRow({
    super.key,
    required this.child,
    required this.isDark,
    this.onRemove,
    this.removeKey,
    this.removeTooltip = 'Remove',
    this.alwaysShow = false,
    this.showBottomBorder = false,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  @override
  State<PlainHoverRemoveRow> createState() => _PlainHoverRemoveRowState();
}

class _PlainHoverRemoveRowState extends State<PlainHoverRemoveRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final showRemove = widget.onRemove != null &&
        (widget.alwaysShow || _hovered || _focused);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: widget.padding,
        decoration: widget.showBottomBorder
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.borderFor(widget.isDark),
                    width: 1,
                  ),
                ),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: widget.child),
            if (widget.onRemove != null)
              Focus(
                onFocusChange: (focused) => setState(() => _focused = focused),
                child: Opacity(
                  opacity: showRemove ? 1.0 : 0.0,
                  child: Tooltip(
                    message: widget.removeTooltip,
                    child: InkWell(
                      key: widget.removeKey,
                      onTap: widget.onRemove,
                      borderRadius: BorderRadius.circular(2),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          '×',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.0,
                            fontWeight: FontWeight.w500,
                            color: _hovered || _focused
                                ? AppTheme.accentRedFor(widget.isDark)
                                : AppTheme.textMutedFor(widget.isDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PlainPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isDark;
  final bool outlined;
  final IconData? icon;
  final Color? fillColor;
  final Color? foregroundColor;

  const PlainPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.isDark,
    this.outlined = false,
    this.icon,
    this.fillColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = outlined
        ? Colors.transparent
        : (fillColor ?? AppTheme.focalAccentFor(isDark));
    final fg = outlined
        ? (foregroundColor ?? AppTheme.textPrimaryFor(isDark))
        : (foregroundColor ?? AppTheme.focalAccentFgFor(isDark));

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor:
            outlined ? Colors.transparent : AppTheme.bgSurfaceActiveFor(isDark),
        disabledForegroundColor: AppTheme.textMutedFor(isDark),
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: outlined
              ? BorderSide(color: AppTheme.borderBrightFor(isDark), width: 1)
              : BorderSide.none,
        ),
        textStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
    );
  }
}

class PlainTextLink extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isDark;
  final Color? color;
  final IconData? icon;
  final double fontSize;
  final FontWeight fontWeight;
  final bool mono;

  const PlainTextLink({
    super.key,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.color,
    this.icon,
    this.fontSize = 12.5,
    this.fontWeight = FontWeight.w500,
    this.mono = false,
  });

  @override
  State<PlainTextLink> createState() => _PlainTextLinkState();
}

class _PlainTextLinkState extends State<PlainTextLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final baseColor = widget.color ?? AppTheme.textSecondaryFor(widget.isDark);
    final activeColor = widget.color ?? AppTheme.textPrimaryFor(widget.isDark);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: widget.fontSize + 1,
                  color: enabled
                      ? (_hovered ? activeColor : baseColor)
                      : AppTheme.textMutedFor(widget.isDark),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: widget.mono ? 'monospace' : null,
                  fontSize: widget.fontSize,
                  fontWeight: widget.fontWeight,
                  color: enabled
                      ? (_hovered ? activeColor : baseColor)
                      : AppTheme.textMutedFor(widget.isDark),
                  decoration: enabled && _hovered
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: activeColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlainDocDivider extends StatelessWidget {
  final bool isDark;
  final double spacing;

  const PlainDocDivider({
    super.key,
    required this.isDark,
    this.spacing = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppTheme.borderFor(isDark),
      ),
    );
  }
}

class PlainBreadcrumbSegment {
  final String label;
  final VoidCallback? onTap;

  const PlainBreadcrumbSegment({required this.label, this.onTap});
}

class PlainBreadcrumbBar extends StatelessWidget {
  final List<PlainBreadcrumbSegment> segments;
  final bool isDark;

  const PlainBreadcrumbBar({
    super.key,
    required this.segments,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        for (int i = 0; i < segments.length; i++) ...[
          if (i > 0)
            Text(
              '/',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: AppTheme.textMutedFor(isDark),
              ),
            ),
          if (segments[i].onTap != null)
            PlainTextLink(
              label: segments[i].label,
              onTap: segments[i].onTap,
              isDark: isDark,
              mono: true,
              fontSize: 11.5,
              color: AppTheme.textSecondaryFor(isDark),
            )
          else
            Text(
              segments[i].label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimaryFor(isDark),
              ),
            ),
        ],
      ],
    );
  }
}
